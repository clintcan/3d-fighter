extends Node
## Online play across scenes: owns the NetPeer from the online menu through character
## select, stage select and the fight, and handles the lobby messages.
##   Host = Player 1 (left), guest = Player 2. Each picks a fighter; the host picks the
##   stage and sends START (fighters, stage, seed, input delay); both go to the VS screen
##   and the fight, where NetplayMatch runs the rollback session.
##   After a match: Rematch (both must ask; the host restarts), Character Select (both go
##   back to the lobby), or Leave.
## The peer is polled in _physics_process, before the fight scene's own physics (autoloads
## come first in the tree), so incoming inputs are in before each tick.

signal connected
signal connect_failed(reason: String)
## Host: a player asks to join (accept_join() / decline_join()); they gave up.
signal join_requested(name: String)
signal join_cancelled(name: String)
## Guest: the host is deciding.
signal join_pending(host_name: String)
signal lobby_changed
signal rematch_changed
signal left(reason: String)

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const ONLINE_MENU_SCENE := "res://scenes/online_menu.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const VS_SCENE := "res://scenes/vs_screen.tscn"

# Reliable lobby message types.
const M_PICK := 1 # u8 roster index (255 = undecided)
const M_START := 2 # u8 stage, u32 seed, u8 P1 fighter, u8 P2 fighter, u8 input delay, u8 rematch
const M_REMATCH := 3
const M_LOBBY := 4

var peer: NetPeer
var local_index := 0 # 0 = host (P1), 1 = guest (P2)
var local_pick := -1
var remote_pick := -1
var input_delay := 2
var rematch_local := false
var rematch_remote := false
## Why the last connection ended (shown by the online menu).
var last_reason := ""
## `-- --smoke-test --online-host` / `--online-join=ip`: pick automatically, play random
## inputs and print checksums (two-process packaging check).
var smoke := false
## Tests: a clock (msec) given to every new peer, so they can run faster than real time.
var peer_clock := Callable()


func _ready() -> void:
	# The host's RSA key takes a second or more of CPU: make it in the background at boot,
	# so hosting never waits for it.
	NetPeer.prepare_host_key()


func _exit_tree() -> void:
	if peer:
		peer.close()
	NetPeer.shutdown_host_key() # quitting with the key task never waited for crashes


func _physics_process(_delta: float) -> void:
	if peer:
		peer.poll()


func host(port: int = NetPeer.DEFAULT_PORT) -> Error:
	_new_peer()
	local_index = 0
	var err := peer.host(port)
	if err != OK:
		peer = null
	return err


func join(address: String) -> Error:
	var parts := address.strip_edges().split(":")
	var ip := parts[0]
	var port := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else NetPeer.DEFAULT_PORT
	if not ip.is_valid_ip_address():
		var resolved := IP.resolve_hostname(ip, IP.TYPE_IPV4)
		if resolved == "":
			return ERR_CANT_RESOLVE
		ip = resolved
	_new_peer()
	local_index = 1
	var err := peer.join(ip, port)
	if err != OK:
		peer = null
	return err


## Host: let the player who asked in, or turn them away.
func accept_join() -> void:
	if peer:
		peer.accept_join()


func decline_join() -> void:
	if peer:
		peer.decline_join()


func is_active() -> bool:
	return peer != null and peer.is_connected_to_peer()


func is_host() -> bool:
	return local_index == 0


func opponent_name() -> String:
	return peer.remote_name if peer else ""


## The connection's security code ("123 456"): the same on both screens unless someone
## is intercepting the connection.
func security_code() -> String:
	return peer.security_code if peer else ""


func rtt_ms() -> float:
	return peer.rtt_ms if peer else 0.0


## Closes the connection (telling the opponent) and forgets the lobby.
func leave() -> void:
	if peer:
		var old := peer
		peer = null
		old.close()
	_reset_lobby()


# --- Lobby -----------------------------------------------------------------------

func pick(index: int) -> void:
	local_pick = index
	if is_active():
		peer.send_reliable(M_PICK, PackedByteArray([index if index >= 0 else 255]))
	lobby_changed.emit()


func both_picked() -> bool:
	return local_pick >= 0 and remote_pick >= 0


## Host only: fixes the match (fighters, stage, seed, input delay), tells the guest, and
## goes to the VS screen (or straight to the fight for a rematch).
func start_match(stage_path: String, rematch: bool = false) -> void:
	if not is_host() or not is_active() or not both_picked():
		return
	var stage_index := maxi(GameState.stage_paths().find(stage_path), 0)
	var seed := randi() & 0x7FFFFFFF
	var delay := recommended_delay()
	var out := StreamPeerBuffer.new()
	out.put_u8(stage_index)
	out.put_u32(seed)
	out.put_u8(local_pick)
	out.put_u8(remote_pick)
	out.put_u8(delay)
	out.put_u8(1 if rematch else 0)
	peer.send_reliable(M_START, out.data_array)
	_begin_match(stage_index, seed, local_pick, remote_pick, delay, rematch)


## Input delay for the current ping: about the one-way trip in ticks plus one, 1..3.
## Rollback covers the rest.
func recommended_delay() -> int:
	return clampi(roundi(rtt_ms() * 0.5 / (1000.0 / 60.0)) + 1, 1, 3)


func request_rematch() -> void:
	rematch_local = true
	if is_active():
		peer.send_reliable(M_REMATCH)
	rematch_changed.emit()
	_check_rematch()


## Both players back to character select.
func back_to_lobby() -> void:
	if is_active():
		peer.send_reliable(M_LOBBY)
	_enter_lobby()


func _check_rematch() -> void:
	if rematch_local and rematch_remote and is_host():
		start_match(GameState.stage_path, true)


func _begin_match(stage_index: int, seed: int, p1: int, p2: int, delay: int, rematch: bool) -> void:
	GameState.mode = GameState.Mode.ONLINE
	GameState.player_character = GameState.roster[p1]
	GameState.p2_character = GameState.roster[p2]
	GameState.stage_path = GameState.stage_paths()[stage_index]
	GameState.match_seed = seed
	input_delay = delay
	rematch_local = false
	rematch_remote = false
	if rematch or smoke:
		GameState.go_to_fight(get_tree())
	else:
		get_tree().change_scene_to_file(VS_SCENE)


func _enter_lobby() -> void:
	_reset_lobby()
	GameState.mode = GameState.Mode.ONLINE
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _reset_lobby() -> void:
	local_pick = -1
	remote_pick = -1
	rematch_local = false
	rematch_remote = false


# --- Peer events -----------------------------------------------------------------

func _new_peer() -> void:
	if peer:
		peer.close()
	_reset_lobby()
	last_reason = ""
	peer = NetPeer.new(GameState.game_version(), GameState.content_hash(), Settings.online_name())
	_apply_lag_args(peer)
	if peer_clock.is_valid():
		peer.clock = peer_clock
	peer.auto_accept = smoke # players are asked; smoke tests let the guest straight in
	peer.join_requested.connect(func(name: String) -> void: join_requested.emit(name))
	peer.join_cancelled.connect(func(name: String) -> void: join_cancelled.emit(name))
	peer.join_pending.connect(func(name: String) -> void: join_pending.emit(name))
	peer.connected.connect(_on_connected)
	peer.connect_failed.connect(_on_connect_failed)
	peer.disconnected.connect(_on_disconnected)
	peer.message_received.connect(_on_message)


## `--net-lag=MS --net-jitter=MS --net-loss=PERCENT`: the lag simulator, for testing.
func _apply_lag_args(target: NetPeer) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--net-lag="):
			target.lag_ms = int(arg.get_slice("=", 1))
		elif arg.begins_with("--net-jitter="):
			target.jitter_ms = int(arg.get_slice("=", 1))
		elif arg.begins_with("--net-loss="):
			target.loss = float(arg.get_slice("=", 1)) / 100.0


func _on_connected() -> void:
	connected.emit()
	if smoke:
		print("SMOKE TEST: online connected to %s, security code %s" % [peer.remote_name, peer.security_code])
		pick(local_index) # host Kenji, guest Rhea


func _on_connect_failed(reason: String) -> void:
	peer = null
	last_reason = reason
	connect_failed.emit(reason)
	if smoke:
		print("SMOKE TEST: online connect failed (%s)" % reason)
		get_tree().quit(1)


func _on_disconnected(reason: String) -> void:
	peer = null
	last_reason = reason
	_reset_lobby()
	left.emit(reason)
	# Outside a fight (lobby screens), go back to the online menu, which shows why.
	# In a fight NetplayMatch shows it and offers the way out.
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("save_state"):
		get_tree().change_scene_to_file(ONLINE_MENU_SCENE)


func _on_message(type: int, payload: PackedByteArray) -> void:
	match type:
		M_PICK:
			remote_pick = payload[0] if payload.size() > 0 and payload[0] < GameState.roster.size() else -1
			lobby_changed.emit()
			if smoke and is_host() and both_picked():
				start_match(GameState.DEFAULT_STAGE)
		M_START:
			if payload.size() < 9:
				return
			var buffer := StreamPeerBuffer.new()
			buffer.data_array = payload
			var stage_index := buffer.get_u8()
			var seed := buffer.get_u32()
			var p1 := buffer.get_u8()
			var p2 := buffer.get_u8()
			var delay := buffer.get_u8()
			var rematch := buffer.get_u8() == 1
			if stage_index < GameState.STAGES.size() and p1 < GameState.roster.size() and p2 < GameState.roster.size():
				local_pick = p2
				remote_pick = p1
				_begin_match(stage_index, seed, p1, p2, delay, rematch)
		M_REMATCH:
			rematch_remote = true
			rematch_changed.emit()
			_check_rematch()
		M_LOBBY:
			_enter_lobby()
