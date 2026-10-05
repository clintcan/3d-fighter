class_name SpectatorFeed
extends RefCounted
## The spectator feed (the lobby server's AGENTS.md section 8): what a match needs to be
## watched, as binary frames sent over the lobby WebSocket. The simulation is
## deterministic, so the match setup plus both players' confirmed inputs reproduce the
## fight exactly on a spectator's machine, at about 240 bytes a second.
##   MATCH_START  u8 1, u16 feed version, u32 match id (seed), u8 stage, u8 P1, u8 P2,
##                six u8-length strings: game version, stage id, P1 id, P2 id, P1 name, P2 name
##   INPUTS       u8 2, u32 match id, u32 first tick, u16 count, count × (u16 P1, u16 P2)
##   CHECKSUM     u8 3, u32 match id, u32 tick, u32 checksum (of the state before that tick)
##   MATCH_END    u8 4, u32 match id, u32 final tick, u8 result, u8 P1 wins, u8 P2 wins
##   FEED_RESET   u8 5, u32 match id (server → spectators: the log was lost)
## Inputs are the screen-relative words the RollbackSession runs on (InputBuffer.pack).
## Publisher turns a session into frames; Log collects them on the spectator's side.

const F_MATCH_START := 1
const F_INPUTS := 2
const F_CHECKSUM := 3
const F_MATCH_END := 4
const F_FEED_RESET := 5
const FEED_VERSION := 1
const MAX_INPUTS := 600
const MAX_STRING := 64
enum Result { P1_WON, P2_WON, DRAW, ABORTED }


static func match_start(match_id: int, stage_index: int, p1: int, p2: int, strings: PackedStringArray) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(F_MATCH_START)
	out.put_u16(FEED_VERSION)
	out.put_u32(match_id & 0xFFFFFFFF)
	out.put_u8(stage_index)
	out.put_u8(p1)
	out.put_u8(p2)
	for i in 6:
		var utf8 := _clip_utf8(strings[i] if i < strings.size() else "")
		out.put_u8(utf8.size())
		out.put_data(utf8)
	return out.data_array


static func inputs(match_id: int, first_tick: int, p1: PackedInt32Array, p2: PackedInt32Array) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(F_INPUTS)
	out.put_u32(match_id & 0xFFFFFFFF)
	out.put_u32(first_tick)
	out.put_u16(p1.size())
	for i in p1.size():
		out.put_u16(p1[i])
		out.put_u16(p2[i])
	return out.data_array


static func checksum(match_id: int, tick: int, value: int) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(F_CHECKSUM)
	out.put_u32(match_id & 0xFFFFFFFF)
	out.put_u32(tick)
	out.put_u32(value & 0xFFFFFFFF)
	return out.data_array


static func match_end(match_id: int, final_tick: int, result: int, p1_wins: int, p2_wins: int) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(F_MATCH_END)
	out.put_u32(match_id & 0xFFFFFFFF)
	out.put_u32(final_tick)
	out.put_u8(result)
	out.put_u8(p1_wins)
	out.put_u8(p2_wins)
	return out.data_array


## A frame as a Dictionary ({type, match_id, ...}), or {} when it's malformed: wrong size,
## bad version, or an input word that isn't a direction 1-9 plus the five buttons.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 5:
		return {}
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	var type := buffer.get_u8()
	match type:
		F_MATCH_START:
			if bytes.size() < 12 or buffer.get_u16() != FEED_VERSION:
				return {}
			var out := {type = type, match_id = buffer.get_u32(), stage = buffer.get_u8(), p1 = buffer.get_u8(), p2 = buffer.get_u8()}
			var strings := PackedStringArray()
			for i in 6:
				if buffer.get_available_bytes() < 1:
					return {}
				var length := buffer.get_u8()
				if length > MAX_STRING or buffer.get_available_bytes() < length:
					return {}
				strings.append((buffer.get_data(length)[1] as PackedByteArray).get_string_from_utf8())
			if buffer.get_available_bytes() != 0:
				return {}
			out.merge({game_version = strings[0], stage_id = strings[1], p1_id = strings[2], p2_id = strings[3],
				p1_name = NetPeer.clean_name(strings[4]), p2_name = NetPeer.clean_name(strings[5])})
			return out
		F_INPUTS:
			if bytes.size() < 11:
				return {}
			var match_id := buffer.get_u32()
			var first := buffer.get_u32()
			var count := buffer.get_u16()
			if count == 0 or count > MAX_INPUTS or bytes.size() != 11 + count * 4:
				return {}
			var p1 := PackedInt32Array()
			var p2 := PackedInt32Array()
			p1.resize(count)
			p2.resize(count)
			for i in count:
				p1[i] = buffer.get_u16()
				p2[i] = buffer.get_u16()
				if not valid_input(p1[i]) or not valid_input(p2[i]):
					return {}
			return {type = type, match_id = match_id, first = first, p1 = p1, p2 = p2}
		F_CHECKSUM:
			if bytes.size() != 13:
				return {}
			return {type = type, match_id = buffer.get_u32(), tick = buffer.get_u32(), checksum = buffer.get_u32()}
		F_MATCH_END:
			if bytes.size() != 12:
				return {}
			var out := {type = type, match_id = buffer.get_u32(), final_tick = buffer.get_u32(), result = buffer.get_u8(),
				p1_wins = buffer.get_u8(), p2_wins = buffer.get_u8()}
			return out if out.result <= Result.ABORTED else {}
		F_FEED_RESET:
			if bytes.size() != 5:
				return {}
			return {type = type, match_id = buffer.get_u32()}
	return {}


## Direction 1-9 in bits 0-3, buttons in bits 4-8, nothing else.
static func valid_input(word: int) -> bool:
	var dir := word & 0xF
	return dir >= 1 and dir <= 9 and word & ~0x1FF == 0


## At most MAX_STRING bytes of UTF-8, cut on a character boundary.
static func _clip_utf8(text: String) -> PackedByteArray:
	var utf8 := text.to_utf8_buffer()
	while utf8.size() > MAX_STRING:
		text = text.left(text.length() - 1)
		utf8 = text.to_utf8_buffer()
	return utf8


## Publishes a match from a RollbackSession: MATCH_START, then confirmed inputs in batches
## (every BATCH_TICKS ticks or FLUSH_MS), checksums once their tick is published, and
## MATCH_END. Confirmed inputs can't change any more, so spectators get the real match.
class Publisher:
	const BATCH_TICKS := 6
	const FLUSH_MS := 100

	var session: RollbackSession
	var match_id := 0
	var published := 0 # ticks sent
	var ended := false
	var _send: Callable # func(bytes: PackedByteArray)
	var _next_checksum := RollbackSession.CHECKSUM_INTERVAL
	var _last_flush := 0

	func _init(rollback: RollbackSession, send: Callable) -> void:
		session = rollback
		match_id = rollback.match_id
		_send = send

	func start(stage_index: int, p1: int, p2: int, strings: PackedStringArray) -> void:
		_send.call(SpectatorFeed.match_start(match_id, stage_index, p1, p2, strings))

	## Once per real tick, after the session advanced.
	func update(now_ms: int) -> void:
		if ended:
			return
		var ready := session.confirmed_frame() + 1 - published
		if ready >= BATCH_TICKS or (ready > 0 and now_ms - _last_flush >= FLUSH_MS):
			_flush(now_ms)

	## The match is over (its result is confirmed): everything left, then MATCH_END.
	func finish(result: int, p1_wins: int, p2_wins: int, now_ms: int) -> void:
		if ended:
			return
		_flush(now_ms)
		ended = true
		_send.call(SpectatorFeed.match_end(match_id, published, result, p1_wins, p2_wins))

	func _flush(now_ms: int) -> void:
		_last_flush = now_ms
		var newest := session.confirmed_frame()
		while published <= newest:
			var count := mini(newest - published + 1, SpectatorFeed.MAX_INPUTS)
			var p1 := PackedInt32Array()
			var p2 := PackedInt32Array()
			for tick in range(published, published + count):
				p1.append(session.confirmed_input(0, tick))
				p2.append(session.confirmed_input(1, tick))
			_send.call(SpectatorFeed.inputs(match_id, published, p1, p2))
			published += count
		# A checksum is sent once its tick is published. The session can confirm inputs
		# (a packet arrived) before it next computes checksums, so wait for one rather
		# than skip it; only one that can't come any more (well behind) is given up.
		while _next_checksum <= published:
			if session.checksums.has(_next_checksum):
				_send.call(SpectatorFeed.checksum(match_id, _next_checksum, session.checksums[_next_checksum]))
			elif published - _next_checksum < RollbackSession.HISTORY:
				break
			_next_checksum += RollbackSession.CHECKSUM_INTERVAL


## A spectator's copy of the current match, filled from frames as they arrive.
class Log:
	var start := {} # the MATCH_START frame
	var p1 := PackedInt32Array()
	var p2 := PackedInt32Array()
	var checksums := {} # tick -> checksum
	var end := {} # the MATCH_END frame, once it came
	var match_id := -1

	func ticks() -> int:
		return p1.size()

	## Adds a decoded frame; returns false if it doesn't fit this match (wrong id, a gap).
	func add(frame: Dictionary) -> bool:
		match int(frame.get("type", 0)):
			SpectatorFeed.F_MATCH_START:
				start = frame
				match_id = frame.match_id
				p1 = PackedInt32Array()
				p2 = PackedInt32Array()
				checksums = {}
				end = {}
				return true
			SpectatorFeed.F_INPUTS:
				if frame.match_id != match_id or frame.first != p1.size():
					return false
				p1.append_array(frame.p1)
				p2.append_array(frame.p2)
				return true
			SpectatorFeed.F_CHECKSUM:
				if frame.match_id != match_id:
					return false
				checksums[frame.tick] = frame.checksum
				return true
			SpectatorFeed.F_MATCH_END:
				if frame.match_id != match_id:
					return false
				end = frame
				return true
		return false
