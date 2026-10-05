class_name LobbyClient
extends RefCounted
## The connection to the online lobby server (a separate Rust service: rooms, joining,
## hole punching / relay and spectating). One WebSocket carrying JSON control messages and
## binary spectator-feed frames, driven by poll() like NetPeer. The wire protocol is the
## server's AGENTS.md, sections 6 and 8.
##   open() connects and sends hello; welcome → `connected`. Every server message after
##   that arrives as `message` (a Dictionary with "type"), every binary frame as
##   `feed_frame`. Dropped connections retry with the resume token for a while, so a
##   short network hiccup keeps the room.

signal connected(welcome: Dictionary)
signal disconnected(reason: String)
signal message(msg: Dictionary)
signal feed_frame(bytes: PackedByteArray)

const PROTOCOL := 1
const SUBPROTOCOL := "3dfighter.lobby.v1"
## A JSON ping this often when otherwise quiet: keeps rtt_ms and the server clock fresh.
const KEEPALIVE_MS := 15000
const CONNECT_TIMEOUT_MS := 10000
## A dropped connection retries this long (the server keeps the session for 30 s).
const RESUME_WINDOW_MS := 25000
const RESUME_RETRY_MS := 2000
const MAX_TEXT := 8192
## A first connection that fails is tried this many more times (a dropped handshake on a
## flaky network shouldn't need the player to press Connect again).
const CONNECT_RETRIES := 2

enum Status { IDLE, CONNECTING, OPEN, RESUMING, CLOSED }

var status := Status.IDLE
var url := ""
## The server's welcome: session_id, region, udp {host, port}, limits, motd, ...
var welcome := {}
## Server clock minus ours (msec), from welcome and pongs: punch times are server times.
var server_offset_ms := 0
## Round trip to the lobby (msec), from pongs.
var rtt_ms := 0.0
## Optional clock override (msec), like NetPeer's.
var clock := Callable()

var _ws := WebSocketPeer.new()
var _hello := {}
var _resume_token := ""
var _opened_at := 0
var _last_sent := 0
var _dropped_at := -1
var _last_retry := 0
var _rid := 0
var _hello_sent := false
var _attempts := 0


## Connects to `server_url` (ws:// or wss://) and introduces this client with `hello`
## (game_version, content_hash, client_id, name, relay_only ...).
func open(server_url: String, hello: Dictionary) -> Error:
	close()
	url = server_url.strip_edges()
	_hello = hello.duplicate()
	_hello.type = "hello"
	_hello.protocol = PROTOCOL
	_attempts = 0
	var err := _connect()
	if err == OK:
		status = Status.CONNECTING
	return err


func is_open() -> bool:
	return status == Status.OPEN


func close() -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close(1000, "bye")
	status = Status.CLOSED
	welcome = {}
	_resume_token = ""
	_dropped_at = -1


## Sends one JSON message: {"type": type, ...fields}. Returns its request id.
func send(type: String, fields: Dictionary = {}) -> String:
	var msg := fields.duplicate()
	msg.type = type
	_rid += 1
	msg.rid = "r%d" % _rid
	if status == Status.OPEN:
		var text := JSON.stringify(msg)
		if text.to_utf8_buffer().size() <= MAX_TEXT:
			_ws.send_text(text)
			_last_sent = _now()
	return msg.rid


## Sends one spectator-feed frame (host / guest publishing).
func send_binary(bytes: PackedByteArray) -> void:
	if status == Status.OPEN:
		_ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


## The server's clock now (msec), for peer_endpoints' punch_at.
func server_now() -> int:
	return _now() + server_offset_ms


func poll() -> void:
	if status == Status.IDLE or status == Status.CLOSED:
		return
	var now := _now()
	_ws.poll()
	var state := _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _hello_sent:
				_hello_sent = true
				_ws.send_text(JSON.stringify(_hello))
			while _ws.get_available_packet_count() > 0:
				var bytes := _ws.get_packet()
				if _ws.was_string_packet():
					_on_text(bytes.get_string_from_utf8(), now)
				elif not bytes.is_empty():
					feed_frame.emit(bytes)
				if status == Status.CLOSED:
					return
			if status == Status.OPEN and now - _last_sent >= KEEPALIVE_MS:
				send("ping", {t = now})
		WebSocketPeer.STATE_CONNECTING:
			if now - _opened_at > CONNECT_TIMEOUT_MS:
				_ws.close()
				if not _retry_first_connection():
					_lost("Couldn't reach the server", now)
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			var reason := _ws.get_close_reason()
			if status == Status.CONNECTING:
				if code != 4000 and _retry_first_connection():
					return
				_finish("Couldn't connect to the server" if reason == "" else "The server refused: %s" % reason)
			elif status == Status.OPEN:
				if code == 4000: # the server closed us on purpose (version, ban, ...)
					_finish("The server closed the connection: %s" % reason)
				else:
					_lost("Lost the server", now)
			elif status == Status.RESUMING:
				if now - _dropped_at > RESUME_WINDOW_MS:
					_finish("Lost the server")
				elif now - _last_retry >= RESUME_RETRY_MS:
					_last_retry = now
					_connect()


# --- Internals -------------------------------------------------------------------

func _connect() -> Error:
	_ws = WebSocketPeer.new()
	_ws.supported_protocols = PackedStringArray([SUBPROTOCOL])
	_ws.inbound_buffer_size = 1 << 22 # spectators can get a long backlog at once
	_ws.outbound_buffer_size = 1 << 20
	_ws.max_queued_packets = 16384
	_opened_at = _now()
	_hello_sent = false
	var tls := TLSOptions.client() if url.begins_with("wss://") else null
	return _ws.connect_to_url(url, tls)


func _retry_first_connection() -> bool:
	if status != Status.CONNECTING or _attempts >= CONNECT_RETRIES:
		return false
	_attempts += 1
	return _connect() == OK


func _on_text(text: String, now: int) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not parsed.get("type") is String:
		return
	var msg: Dictionary = parsed
	if status == Status.CONNECTING or status == Status.RESUMING:
		if msg.type == "welcome":
			welcome = msg
			_resume_token = str(msg.get("resume_token", ""))
			server_offset_ms = int(msg.get("server_time", now)) - now
			var resumed := status == Status.RESUMING
			status = Status.OPEN
			_dropped_at = -1
			_last_sent = now
			if not resumed:
				connected.emit(welcome)
			return
		if msg.type == "error":
			_finish(error_text(msg))
			return
	match msg.type:
		"pong":
			var sample := float(now - int(msg.get("t", now)))
			if sample >= 0.0 and sample < 10000.0:
				rtt_ms = sample if rtt_ms == 0.0 else lerpf(rtt_ms, sample, 0.25)
				server_offset_ms = int(msg.get("server_time", now)) - (now - roundi(sample * 0.5))
	message.emit(msg)


## The WebSocket dropped: retry with the resume token while the server keeps our session.
func _lost(reason: String, now: int) -> void:
	if _resume_token == "" or status == Status.CONNECTING:
		_finish(reason)
		return
	status = Status.RESUMING
	_dropped_at = now
	_last_retry = now
	_hello.resume_token = _resume_token
	_connect()


func _finish(reason: String) -> void:
	status = Status.CLOSED
	welcome = {}
	disconnected.emit(reason)


func _now() -> int:
	return clock.call() if clock.is_valid() else Time.get_ticks_msec()


## A readable sentence for a server error message.
static func error_text(msg: Dictionary) -> String:
	match str(msg.get("code", "")):
		"version_unsupported": return "This version of the game is too old for the server: please update"
		"version_mismatch": return "That room runs a different version of the game"
		"room_not_found": return "No such room (it may have closed)"
		"room_full": return "That room is full"
		"room_busy": return "Someone else is asking to join that room: try again in a moment"
		"wrong_password": return "Wrong password"
		"spectating_disabled": return "That room doesn't allow spectators"
		"spectators_full": return "That room has no space for more spectators"
		"rate_limited": return "Slow down a little and try again"
		"name_invalid": return "The server doesn't allow that name"
		"already_in_room": return "You're already in a room"
		"server_full": return "The server is full: try again later"
		"not_allowed": return "Not allowed: %s" % msg.get("message", "")
	return str(msg.get("message", "Server error"))

