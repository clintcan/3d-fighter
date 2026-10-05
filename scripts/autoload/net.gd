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
## Internet play goes through the lobby server (LobbyClient, also owned here): rooms,
## join requests and spectating are server messages; once the server matches two players
## (match_session) the same NetPeer connects them, directly or through the server's relay,
## and everything after that (character select, fight, rematch) is unchanged. Spectators
## get the host's feed (SpectatorFeed) and watch it in the fight scene (SpectatorMatch).

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
## Lobby server: connected (welcome), gone, every message (for the lobby screen).
signal server_connected
signal server_closed(reason: String)
signal server_message(msg: Dictionary)
## Spectating: a reaction from someone in the room; the feed or room ended.
signal reaction_received(from_name: String, emote: String)
signal spectate_closed(reason: String)

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const ONLINE_MENU_SCENE := "res://scenes/online_menu.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const VS_SCENE := "res://scenes/vs_screen.tscn"
const SERVER_LOBBY_SCENE := "res://scenes/server_lobby.tscn"
const EMOTES := ["clap", "fire", "wow", "laugh", "gg", "ouch"]

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

# Lobby server.
var lobby: LobbyClient
## Our room: the latest room object from the server, or {}.
var room := {}
## The room's join code (hosts see it), or "".
var room_code := ""
## Our part in the room: "host", "guest", "pending" (asked to join), "spectator" or "".
var room_role := ""
## Watching a match: the feed of the current match (frames keep arriving while it loads).
var spectating := false
var feed := SpectatorFeed.Log.new()
var spectate_delay_ms := 0
## `--server-host` / `--server-join` / `--server-watch` smoke tests (with --server=URL).
var server_smoke := ""
var _pending_endpoints := {}


func _ready() -> void:
	# The host's RSA key takes a second or more of CPU: make it in the background at boot,
	# so hosting never waits for it.
	NetPeer.prepare_host_key()


func _exit_tree() -> void:
	if peer:
		peer.close()
	NetPeer.shutdown_host_key() # quitting with the key task never waited for crashes


func _physics_process(_delta: float) -> void:
	if lobby:
		lobby.poll()
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


## Closes the connection (telling the opponent) and forgets the lobby. In an internet
## room, leaves the room too (a host leaving closes it).
func leave() -> void:
	if peer:
		var old := peer
		peer = null
		old.close()
	_reset_lobby()
	if room_role == "host" or room_role == "guest":
		leave_room()


## Where to go after leaving a match: the internet lobby while connected to the server.
func exit_scene() -> String:
	return SERVER_LOBBY_SCENE if is_server_open() else MAIN_MENU_SCENE


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
	report_room("character_select")
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
	if lobby and peer.server_ip != "":
		lobby.send("connection_report", {path = peer.connection_path(), rtt_ms = clampi(roundi(peer.rtt_ms), 0, 65535)})
		report_room("character_select")
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
	if room_role == "host" or room_role == "guest":
		leave_room() # an internet match that ended: the room goes with it
	left.emit(reason)
	# Outside a fight (lobby screens), go back to the online menu, which shows why.
	# In a fight NetplayMatch shows it and offers the way out.
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("save_state"):
		get_tree().change_scene_to_file(SERVER_LOBBY_SCENE if is_server_open() else ONLINE_MENU_SCENE)


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


# --- Lobby server ----------------------------------------------------------------

## Connects to the lobby server at `url` (ws:// or wss://).
func connect_server(url: String) -> Error:
	disconnect_server()
	lobby = LobbyClient.new()
	lobby.connected.connect(func(_welcome: Dictionary) -> void: server_connected.emit())
	lobby.disconnected.connect(_on_server_lost)
	lobby.message.connect(_on_lobby_message)
	lobby.feed_frame.connect(_on_feed_frame)
	var err := lobby.open(url, {game_version = GameState.game_version(), content_hash = GameState.content_hash() & 0xFFFFFFFF,
		client_id = Settings.get_client_id(), name = Settings.online_name(), relay_only = Settings.relay_only})
	if err != OK:
		lobby = null
	return err


func disconnect_server() -> void:
	if lobby:
		var old := lobby
		lobby = null
		old.close()
	_clear_room()


func is_server_open() -> bool:
	return lobby != null and lobby.is_open()


func list_rooms() -> void:
	if is_server_open():
		lobby.send("list_rooms", {status = "any", compatible_only = false, limit = 50})


## Opens a room (we'll be the host, Player 1). password "" = none.
func create_room(room_name: String, public: bool, password: String, allow_spectators: bool) -> void:
	var fields := {name = room_name, visibility = "public" if public else "unlisted", allow_spectators = allow_spectators}
	if password != "":
		fields.password = password
	lobby.send("create_room", fields)


## Asks to join a room by id or code.
func join_room(room_key: String, password: String = "") -> void:
	var fields := {room = _room_key(room_key)}
	if password != "":
		fields.password = password
	lobby.send("join_room", fields)
	room_role = "pending"


func cancel_join() -> void:
	if is_server_open() and room_role == "pending":
		lobby.send("cancel_join")
	room_role = ""


## Host: lets the player who asked in, or turns them away.
func answer_join(request_id: String, accept: bool) -> void:
	lobby.send("answer_join", {request_id = request_id, accept = accept})


func leave_room() -> void:
	if is_server_open() and room_role != "" and room_role != "pending":
		lobby.send("stop_spectating" if room_role == "spectator" else "leave_room")
	_clear_room()


func spectate_room(room_key: String, password: String = "") -> void:
	var fields := {room = _room_key(room_key)}
	if password != "":
		fields.password = password
	lobby.send("spectate", fields)


func stop_spectating() -> void:
	leave_room()


## Members and spectators: a quick emote everyone in the room sees.
func react(emote: String) -> void:
	if is_server_open() and room_role != "" and room_role != "pending" and emote in EMOTES:
		lobby.send("react", {emote = emote})


## Host: tells the server what the room is doing (the room list shows it).
func report_room(phase: String, extra: Dictionary = {}) -> void:
	if not is_server_open() or room_role != "host":
		return
	var fields := extra.duplicate()
	fields.phase = phase
	lobby.send("room_update", fields)


## Sends a spectator-feed frame (players in an internet room publish their match).
func publish(bytes: PackedByteArray) -> void:
	if is_server_open() and (room_role == "host" or room_role == "guest"):
		lobby.send_binary(bytes)


## Whether this match is an internet room's (and so should publish its feed).
func publishing() -> bool:
	return is_server_open() and peer != null and peer.server_ip != ""


## Room codes are typed in any case; room ids pass through.
static func _room_key(text: String) -> String:
	var key := text.strip_edges()
	return key.to_upper() if key.length() == 6 else key


func _clear_room() -> void:
	room = {}
	room_code = ""
	room_role = ""
	spectating = false
	feed = SpectatorFeed.Log.new()
	_pending_endpoints = {}


func _on_server_lost(reason: String) -> void:
	lobby = null
	var was_watching := spectating
	_clear_room()
	if was_watching:
		spectate_closed.emit(reason)
	server_closed.emit(reason)
	# A match already running keeps going: it's player to player, the server only matched us.


func _on_lobby_message(msg: Dictionary) -> void:
	match str(msg.type):
		"room_created":
			room = msg.get("room", {})
			room_code = str(msg.get("code", ""))
			room_role = "host"
		"room_state":
			if room_role != "" and room_role != "pending":
				room = msg.get("room", {})
		"join_declined":
			room_role = ""
		"match_session":
			_start_server_peer(msg)
		"peer_endpoints":
			_on_peer_endpoints(msg)
		"player_left":
			if room_role == "host" and peer and not peer.is_connected_to_peer():
				# The guest left before the connection was up: wait for someone else.
				var old := peer
				peer = null
				old.close()
			elif room_role == "guest" and str(msg.get("reason", "")) == "kicked":
				_clear_room()
		"room_closed":
			var was_watching := spectating
			_clear_room()
			if was_watching:
				spectate_closed.emit("The room closed")
		"spectate_started":
			room_role = "spectator"
			spectating = true
			spectate_delay_ms = int(msg.get("delay_ms", 0))
			feed = SpectatorFeed.Log.new()
		"spectate_ended":
			_clear_room()
			spectate_closed.emit("Too far behind the match" if msg.get("reason") == "too_slow" else "Spectating ended")
		"reaction":
			reaction_received.emit(NetPeer.clean_name(str(msg.get("name", ""))), str(msg.get("emote", "")))
		"error":
			if room_role == "pending":
				room_role = ""
	server_message.emit(msg)
	if server_smoke != "":
		_server_smoke_step(msg)


## The server matched us: the same NetPeer handshake, over the server's rendezvous.
func _start_server_peer(msg: Dictionary) -> void:
	var udp: Dictionary = msg.get("udp", {})
	var host_name := str(udp.get("host", ""))
	var ip := host_name if host_name.is_valid_ip_address() else IP.resolve_hostname(host_name, IP.TYPE_IPV4)
	var token := str(msg.get("session_token", "")).hex_decode()
	var key := str(msg.get("relay_key", "")).hex_decode()
	if ip == "" or token.size() != 16 or key.size() != 8:
		last_reason = "The server sent a connection this game can't use"
		connect_failed.emit(last_reason)
		return
	var as_host := str(msg.get("role", "")) == "host"
	_new_peer()
	local_index = 0 if as_host else 1
	var err := peer.host(0) if as_host else peer.join_via_server()
	if err != OK:
		peer = null
		last_reason = "Couldn't open a network port (%s)" % error_string(err)
		connect_failed.emit(last_reason)
		return
	peer.use_server(ip, int(udp.get("port", 0)), token, key, as_host)
	room_role = "host" if as_host else "guest"
	if not _pending_endpoints.is_empty():
		_on_peer_endpoints(_pending_endpoints)


func _on_peer_endpoints(msg: Dictionary) -> void:
	if peer == null or peer.server_ip == "":
		_pending_endpoints = msg # arrived before match_session was handled
		return
	_pending_endpoints = {}
	if peer.is_connected_to_peer():
		return # a NAT rebind notice: the connection we have is fine
	var candidates: Variant = msg.get("candidates", [])
	peer.set_peer_candidates(candidates if candidates is Array else [], int(msg.get("punch_at", 0)) - lobby.server_now())


## Spectating: collect the feed; a new match (MATCH_START) loads the fight to watch it.
func _on_feed_frame(bytes: PackedByteArray) -> void:
	if not spectating:
		return
	var frame := SpectatorFeed.decode(bytes)
	if frame.is_empty():
		return
	match int(frame.type):
		SpectatorFeed.F_MATCH_START:
			var problem := watch_problem(frame)
			if problem != "":
				leave_room()
				spectate_closed.emit(problem)
				return
			feed = SpectatorFeed.Log.new()
			feed.add(frame)
			GameState.mode = GameState.Mode.ONLINE
			GameState.player_character = GameState.roster[frame.p1]
			GameState.p2_character = GameState.roster[frame.p2]
			GameState.stage_path = GameState.stage_paths()[frame.stage]
			GameState.match_seed = frame.match_id
			GameState.go_to_fight(get_tree())
		SpectatorFeed.F_FEED_RESET:
			feed = SpectatorFeed.Log.new()
		_:
			feed.add(frame)


## Why this machine can't watch a match ("" = it can): replaying it needs the same game.
func watch_problem(start: Dictionary) -> String:
	if start.game_version != GameState.game_version():
		return "That match runs version %s of the game" % start.game_version
	if start.stage >= GameState.STAGES.size() or start.p1 >= GameState.roster.size() or start.p2 >= GameState.roster.size():
		return "That match uses fighters or stages this version doesn't have"
	if str(GameState.roster[start.p1].id) != start.p1_id or str(GameState.roster[start.p2].id) != start.p2_id:
		return "That match's fighters don't match this version"
	return ""


# --- Lobby server smoke tests ----------------------------------------------------

## `-- --smoke-test --server=URL --server-host` (open a room and play whoever joins),
## `--server-join` (join the first open room) or `--server-watch` (watch the first match).
func start_server_smoke(url: String, role: String) -> Error:
	server_smoke = role
	smoke = role != "watch"
	Settings.client_id = Settings.new_uuid() # each process its own player (never saved)
	Settings.player_name = "Smoke %s" % role.capitalize()
	Settings.relay_only = "--relay-only" in OS.get_cmdline_user_args()
	server_connected.connect(func() -> void:
		print("SMOKE TEST: server connected (region %s)" % lobby.welcome.get("region", "?"))
		if role == "host":
			create_room("Smoke %d" % (randi() % 1000), true, "", true)
		else:
			list_rooms(), CONNECT_ONE_SHOT)
	server_closed.connect(func(reason: String) -> void:
		print("SMOKE TEST: server connection closed (%s)" % reason))
	spectate_closed.connect(func(reason: String) -> void:
		print("SMOKE TEST: spectating ended (%s)" % reason)
		get_tree().quit())
	return connect_server(url)


func _server_smoke_step(msg: Dictionary) -> void:
	match str(msg.type):
		"rooms":
			if room_role != "":
				return
			for r: Dictionary in msg.get("rooms", []):
				if not r.get("compatible", false):
					continue
				if server_smoke == "join" and r.get("status") == "open":
					print("SMOKE TEST: server joining room %s" % r.get("name"))
					join_room(str(r.id))
					return
				if server_smoke == "watch" and r.get("status") == "in_match" and r.get("allow_spectators", false):
					print("SMOKE TEST: server watching room %s" % r.get("name"))
					spectate_room(str(r.id))
					return
			get_tree().create_timer(0.5).timeout.connect(list_rooms)
		"room_created":
			print("SMOKE TEST: server room %s created" % msg.get("code"))
		"join_request":
			print("SMOKE TEST: server join request from %s" % msg.get("name"))
			answer_join(str(msg.request_id), true)
		"match_session":
			print("SMOKE TEST: server matched as %s with %s" % [msg.get("role"), msg.get("peer", {}).get("name")])
		"peer_endpoints":
			print("SMOKE TEST: server peer endpoints, %d candidate(s)" % msg.get("candidates", []).size())
		"spectate_started":
			print("SMOKE TEST: server spectating (delay %d ms, live %s)" % [msg.get("delay_ms", 0), msg.get("match_live", false)])
		"error":
			print("SMOKE TEST: server error %s (%s)" % [msg.get("code"), msg.get("message")])
			if server_smoke == "watch" or server_smoke == "join":
				get_tree().create_timer(0.5).timeout.connect(list_rooms)
