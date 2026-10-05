class_name RollbackSession
extends RefCounted
## GGPO-style rollback netcode for one peer. Drives a FightManager one tick at a time:
##   - local input is scheduled `input_delay` ticks ahead;
##   - the remote player's missing input is predicted (their last confirmed input);
##   - when the real input arrives and differs from the prediction, the simulation is
##     restored to that tick and re-run up to the present with the correct inputs
##     (FightManager.resimulating mutes effects and sounds meanwhile);
##   - the session stalls rather than running more than MAX_ROLLBACK ticks ahead of the
##     last confirmed remote input, and waits a tick now and then when it's running
##     ahead of the peer (time sync), so neither side has to roll back much more;
##   - every CHECKSUM_INTERVAL ticks both peers hash the confirmed state and compare.
## It's transport-agnostic: make_packet() / receive_packet() turn its traffic into bytes,
## and the network layer just delivers them (unreliably is fine: inputs are resent until
## acknowledged).
## Inputs are screen-relative (PlayerController.read_raw) and converted to facing-relative
## inside the tick by each fighter's NetInputController.

signal desynced(frame: int, local_checksum: int, remote_checksum: int)

const MAX_ROLLBACK := 8
const CHECKSUM_INTERVAL := 60
const MAX_PACKET_INPUTS := 32
const HISTORY := 120 # ticks of inputs and states kept
const SYNC_INTERVAL := 12 # at most one time-sync wait per this many ticks
const SYNC_SMOOTHING := 0.05 # weight of each new sample in the advantage averages
const PACKET_INPUT := 1
const HEADER_SIZE := 27 # INPUT packet bytes before the inputs: 1+4+4+4+1+4+4+4+1
## How far (ticks) the peer can honestly be ahead of us: it can't run more than
## MAX_ROLLBACK past our inputs, which are at most input_delay ahead. Anything beyond this
## generous bound is bogus and dropped, so a hostile packet can't poison time sync, fill
## memory with far-future inputs or checksums, or freeze the match with a fake ack.
const MAX_LEAD := 60
const MAX_ADVANTAGE := 30
const NEUTRAL := 5 # InputBuffer.pack(InputBuffer.NEUTRAL, 0)

var manager: Node # FightManager
var local_player := 0
var remote_player := 1
var input_delay := 2
## Identifies this match in every packet (both peers use the seed from START), so a late
## packet from the previous match (a rematch starts at slightly different times on each
## machine) is ignored instead of corrupting time sync and checksums.
var match_id := 0
## The next tick to simulate (= ticks simulated so far).
var frame := 0
## Round trip time in ticks, set by the network layer (used for time sync).
var rtt_ticks := 0.0

# Stats, for the connection HUD and tests.
var rollbacks := 0
var rollback_ticks := 0 # total ticks re-simulated
var last_rollback := 0 # ticks re-simulated by the latest rollback
var stalls := 0 # ticks waited for remote input
var sync_waits := 0 # ticks waited for time sync
var desync_frame := -1
## tick -> checksum of the confirmed state before that tick (kept for the whole match).
var checksums := {}

var remote_frame := -1 # the newest tick the peer has reported simulating
var remote_advantage := 0 # the peer's view of how far ahead of us it is

var _controllers: Array[NetInputController] = []
var _inputs: Array[Dictionary] = [{}, {}] # per player: tick -> screen-relative input (confirmed)
var _predicted := {} # tick -> remote input guessed when that tick was simulated
var _states := {} # tick -> FightManager snapshot taken before simulating it
var _remote_confirmed := -1 # every remote input up to this tick is known
var _remote_acked := -1 # the peer has every local input up to this tick
var _local_newest := -1
var _rollback_from := -1 # earliest tick simulated with a wrong prediction
var _local_checksums := {}
var _remote_checksums := {}
var _last_sync_wait := -SYNC_INTERVAL
# Smoothed advantages, so network jitter doesn't trigger waits on both sides.
var _local_adv_avg := 0.0
var _remote_adv_avg := 0.0


## Takes over `fight_manager`'s fighters with NetInputControllers. The caller stops the
## manager's own _physics_process and calls advance() once per tick instead.
func _init(fight_manager: Node, local_index: int, delay: int = 2, match_identifier: int = 0) -> void:
	manager = fight_manager
	match_id = match_identifier & 0xFFFFFFFF
	local_player = local_index
	remote_player = 1 - local_index
	input_delay = delay
	for fighter: Fighter in manager.fighters:
		var controller := NetInputController.new()
		fighter.controller = controller
		_controllers.append(controller)
	for tick in input_delay:
		_inputs[local_player][tick] = NEUTRAL
	_local_newest = input_delay - 1


## One real tick: schedules the local input, rolls back if a prediction was wrong, then
## simulates the next tick. Returns false when it had to wait (stall or time sync).
func advance(local_input: int) -> bool:
	var target := frame + input_delay
	if not _inputs[local_player].has(target):
		_inputs[local_player][target] = local_input
		_local_newest = maxi(_local_newest, target)
	if _rollback_from >= 0:
		_rollback()
	if frame - _remote_confirmed > MAX_ROLLBACK:
		stalls += 1
		return false
	if _should_wait_for_sync():
		sync_waits += 1
		_last_sync_wait = frame
		return false
	_simulate(frame)
	frame += 1
	_update_checksums()
	_trim()
	return true


## Ticks simulated with every input known: these can never be rolled back.
func confirmed_frame() -> int:
	return mini(_remote_confirmed, frame - 1)


## A player's screen-relative input for a confirmed tick (the spectator feed publishes
## these). Recent ticks only: older ones are trimmed after HISTORY ticks.
func confirmed_input(player: int, tick: int) -> int:
	return _inputs[player].get(tick, NEUTRAL)


## How many ticks the newest simulated tick is ahead of the last confirmed one.
func prediction_depth() -> int:
	return frame - 1 - confirmed_frame()


## Local advantage in ticks: positive when this peer is ahead of the peer's estimated
## current tick.
func local_advantage() -> int:
	if remote_frame < 0:
		return 0
	return frame - (remote_frame + roundi(rtt_ticks * 0.5))


# --- Simulation -----------------------------------------------------------------

func _simulate(tick: int) -> void:
	_states[tick] = manager.save_state()
	_controllers[local_player].raw = _inputs[local_player][tick]
	var remote_inputs: Dictionary = _inputs[remote_player]
	if remote_inputs.has(tick):
		_controllers[remote_player].raw = remote_inputs[tick]
		_predicted.erase(tick)
	else:
		var guess: int = remote_inputs.get(_remote_confirmed, NEUTRAL)
		_controllers[remote_player].raw = guess
		_predicted[tick] = guess
	manager.step()


func _rollback() -> void:
	var start := _rollback_from
	_rollback_from = -1
	var end := frame
	manager.load_state(_states[start])
	manager.resimulating = true
	for tick in range(start, end):
		_simulate(tick)
	manager.resimulating = false
	rollbacks += 1
	last_rollback = end - start
	rollback_ticks += last_rollback


func _should_wait_for_sync() -> bool:
	if remote_frame < 0:
		return false
	_local_adv_avg = lerpf(_local_adv_avg, local_advantage(), SYNC_SMOOTHING)
	if frame - _last_sync_wait < SYNC_INTERVAL:
		return false
	# Both sides estimate their advantage; the one further ahead waits half the gap.
	return (_local_adv_avg - _remote_adv_avg) * 0.5 >= 1.0


func _update_checksums() -> void:
	# The state before tick c is final once every input before c is confirmed.
	var newest := mini(confirmed_frame() + 1, frame - 1)
	var c := newest - newest % CHECKSUM_INTERVAL
	if c <= 0 or _local_checksums.has(c) or not _states.has(c):
		return
	_local_checksums[c] = manager.checksum(_states[c])
	checksums[c] = _local_checksums[c]
	_compare_checksum(c)


func _compare_checksum(c: int) -> void:
	if desync_frame >= 0 or not _local_checksums.has(c) or not _remote_checksums.has(c):
		return
	if _local_checksums[c] != _remote_checksums[c]:
		desync_frame = c
		desynced.emit(c, _local_checksums[c], _remote_checksums[c])


func _trim() -> void:
	var oldest := frame - HISTORY
	for table: Dictionary in [_states, _predicted, _local_checksums, _remote_checksums, _inputs[remote_player]]:
		for tick: int in table.keys():
			if tick < oldest:
				table.erase(tick)
	for tick: int in _inputs[local_player].keys():
		if tick < oldest and tick <= _remote_acked:
			_inputs[local_player].erase(tick)


# --- Packets --------------------------------------------------------------------
# INPUT packet (little-endian): u8 type, u32 match id, s32 newest simulated tick, s32 ack (newest
# contiguous remote tick received), s8 local advantage, s32 checksum tick, u32 checksum,
# s32 first input tick, u8 count, count × u16 inputs.

func make_packet() -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(PACKET_INPUT)
	out.put_u32(match_id)
	out.put_32(frame - 1)
	out.put_32(_remote_confirmed)
	out.put_8(clampi(local_advantage(), -127, 127))
	var checksum_tick := -1
	for c: int in _local_checksums:
		checksum_tick = maxi(checksum_tick, c)
	out.put_32(checksum_tick)
	out.put_u32(_local_checksums.get(checksum_tick, 0))
	var first := _remote_acked + 1
	var count := clampi(_local_newest - first + 1, 0, MAX_PACKET_INPUTS)
	out.put_32(first)
	out.put_u8(count)
	for tick in range(first, first + count):
		out.put_u16(_inputs[local_player][tick])
	return out.data_array


func receive_packet(bytes: PackedByteArray) -> void:
	if bytes.size() < HEADER_SIZE or bytes[0] != PACKET_INPUT:
		return
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.get_u8()
	if buffer.get_u32() != match_id:
		return # from another match (e.g. the previous one, before a rematch)
	var sender_frame := buffer.get_32()
	var ack := buffer.get_32()
	var advantage := buffer.get_8()
	var checksum_tick := buffer.get_32()
	var checksum := buffer.get_u32()
	var first := buffer.get_32()
	var count := buffer.get_u8()
	if sender_frame > frame + MAX_LEAD or sender_frame < -1 or count > MAX_PACKET_INPUTS \
			or bytes.size() < HEADER_SIZE + count * 2:
		return # impossible for an honest peer
	remote_frame = maxi(remote_frame, sender_frame)
	# The peer can't have inputs we never sent: a bigger ack would stop us resending.
	_remote_acked = maxi(_remote_acked, mini(ack, _local_newest))
	remote_advantage = clampi(advantage, -MAX_ADVANTAGE, MAX_ADVANTAGE)
	_remote_adv_avg = lerpf(_remote_adv_avg, remote_advantage, SYNC_SMOOTHING)
	if checksum_tick > 0 and checksum_tick % CHECKSUM_INTERVAL == 0 and checksum_tick > frame - HISTORY \
			and checksum_tick <= frame + MAX_LEAD:
		_remote_checksums[checksum_tick] = checksum
		_compare_checksum(checksum_tick)
	for i in count:
		add_remote_input(first + i, buffer.get_u16())


## Records a confirmed remote input. Public so tests can bypass packets. Ticks outside
## the plausible window are ignored, and the input is reduced to a real direction plus the
## five buttons.
func add_remote_input(tick: int, input: int) -> void:
	var remote_inputs: Dictionary = _inputs[remote_player]
	if remote_inputs.has(tick) or tick <= _remote_confirmed - HISTORY or tick > frame + MAX_LEAD:
		return
	var dir := input & 0xF
	var clean := (input & (0x1F << InputBuffer.BUTTON_SHIFT)) | (dir if dir >= 1 and dir <= 9 else InputBuffer.NEUTRAL)
	remote_inputs[tick] = clean
	if _predicted.has(tick):
		if _predicted[tick] != clean:
			_rollback_from = tick if _rollback_from < 0 else mini(_rollback_from, tick)
		_predicted.erase(tick)
	while remote_inputs.has(_remote_confirmed + 1):
		_remote_confirmed += 1
