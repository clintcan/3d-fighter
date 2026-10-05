class_name NetPeer
extends RefCounted
## One end of a two-player UDP connection, driven by poll() (no threads, no nodes, so two
## can run side by side in a test).
##
## Handshake. The host commits to nothing until the joiner proves its address:
##   1. guest → HELLO (protocol, game version, data hash, name, random nonce, cookie 0)
##   2. host → CHALLENGE (nonce, cookie): a stateless HMAC of the sender's address and a
##      10 s time window, smaller than the HELLO (no amplification), rate limited.
##   3. guest → HELLO again with the cookie. The address is now proven:
##      - wrong version / data, host busy, or declined → REJECT (with the nonce);
##      - otherwise the host asks its player (join_requested; auto_accept skips this),
##        sending PENDING meanwhile.
##   The guest ignores replies that don't echo its nonce (forged REJECTs can't break a
##   join); a declined address is ignored for DECLINE_BAN_MS.
## Key exchange with a short security code (both players can compare it):
##   4. host → WELCOME (nonce, session token, name, RSA-2048 public key, commitment =
##      SHA-256 of a random host nonce Nh and the key)
##   5. guest → KEY: a random 32-byte secret encrypted to that key, and a guest nonce Ng
##   6. host → KEYOK: Nh. The guest checks it against the commitment.
##   Both derive per-direction AES and HMAC keys from the secret and both nonces, and a
##   6-digit security_code from the whole exchange. Someone in the middle has to pick
##   their values before seeing the other side's nonce (the commitment), so they can't
##   search for matching codes: each attempt has a 1-in-a-million chance.
##   The host decrypts at most one KEY per connection (no decryption oracle).
## After that every datagram is [type][token][counter][AES-256-CBC ciphertext][tag]:
## IV derived per packet, encrypt-then-MAC with HMAC-SHA256 (16-byte tag over type,
## counter and ciphertext), separate keys per direction, and a 64-packet replay window.
## Anything that fails is dropped silently.
##   - PING / PONG every PING_INTERVAL_MS (rtt_ms); silence for timeout_ms = gone; BYE.
##   - send_reliable(): lobby messages, numbered, resent until acknowledged, delivered in
##     order (at most RELIABLE_WINDOW held out of order).
##   - send_input(): unreliable RollbackSession packets.
##   - LAN discovery: a host answers DISCOVER from private addresses only (LanBrowser).
##   - Lag simulator: lag_ms / jitter_ms / loss on outgoing traffic, for testing.
## Internet play through the lobby server (use_server(), after the server matched the two
## players): this socket sends BIND (session token) to the server's UDP port until BOUND,
## then as a keepalive. With the peer's addresses (peer_endpoints) the host punches holes
## (T_PUNCH) and the guest sends its HELLO to every candidate, locking on to the first that
## answers; after PUNCH_TIMEOUT_MS without an answer it goes through the relay instead:
## every datagram wrapped as RELAY [key][datagram] to the server, which forwards it as
## RELAYED [datagram]. The relay is just another address (RELAY_IP) to the handshake, so
## encryption and the security code work the same on both paths. The server already asked
## the host, so the host lets in the expected addresses (and only those) without asking.

signal connected
signal connect_failed(reason: String)
signal disconnected(reason: String)
signal message_received(type: int, payload: PackedByteArray)
signal input_received(bytes: PackedByteArray)
## Host: a verified player asks to join (accept_join() / decline_join()).
signal join_requested(name: String)
## Host: the player asking to join stopped trying.
signal join_cancelled(name: String)
## Guest: the host is deciding whether to let us in.
signal join_pending(host_name: String)

const PROTOCOL := 3
const DEFAULT_PORT := 7777
const HELLO_INTERVAL_MS := 250
const JOIN_TIMEOUT_MS := 10000 # without any answer from the host
const SECURE_TIMEOUT_MS := 10000 # to finish the key exchange
const PING_INTERVAL_MS := 500
const RESEND_INTERVAL_MS := 150
const TIMEOUT_MS := 10000 # generous: a first stage load can stall the main thread for seconds
const COOKIE_WINDOW_MS := 10000
const CANDIDATE_TIMEOUT_MS := 4000 # a joiner silent this long has given up
const DECLINE_BAN_MS := 30000
const RELIABLE_WINDOW := 64
const REPLAY_WINDOW := 64
const MAX_UNVERIFIED_REPLIES := 30 # per second: CHALLENGE + ANNOUNCE
const MAX_VERIFIED_REPLIES := 20 # per second: REJECT + PENDING
const MAX_NAME := 24
const RSA_BITS := 2048
const KEY_CIPHER_SIZE := 256 # RSA_BITS / 8
const TAG_SIZE := 16
const SEALED_HEADER := 17 # type + token + counter

# Datagram types (first byte).
const T_INPUT := 1
const T_HELLO := 10
const T_WELCOME := 11
const T_REJECT := 12
const T_CHALLENGE := 13
const T_PENDING := 14
const T_KEY := 15
const T_KEYOK := 16
const T_PING := 20
const T_PONG := 21
const T_BYE := 30
const T_RELIABLE := 40
const T_ACK := 41
const T_DISCOVER := 50
const T_ANNOUNCE := 51
const T_PUNCH := 52 # opens the NAT toward a peer; ignored on arrival
# Lobby server datagrams (rendezvous and relay; see the server's AGENTS.md section 7).
const S_BIND := 0xF0
const S_BOUND := 0xF1
const S_RELAY := 0xF2
const S_RELAYED := 0xF3
const S_PONG := 0xF5
## The address of a peer reached through the server's relay.
const RELAY_IP := "relay"
const BIND_INTERVAL_MS := 250
const BIND_KEEPALIVE_MS := 15000
const PUNCH_INTERVAL_MS := 100
const PUNCH_TIMEOUT_MS := 3000 # no direct answer by then: use the relay
const ENDPOINTS_TIMEOUT_MS := 15000 # the server never sent the peer's addresses
const MAX_RELAY_PAYLOAD := 1200
const MAX_BIND_CANDIDATES := 4

enum Status { IDLE, HOSTING, JOINING, SECURING, CONNECTED, CLOSED }

## The host's RSA key, made once per run in a background thread (prepare_host_key()).
static var _host_key: CryptoKey
static var _host_key_task := -1

var status := Status.IDLE
var is_host := false
var game_version := ""
var content_hash := 0
var player_name := "Player"
var remote_name := ""
var remote_ip := ""
var remote_port := 0
var rtt_ms := 0.0 # smoothed round trip
var timeout_ms := TIMEOUT_MS
## Host: let verified players in without asking (tests, smoke tests).
var auto_accept := false
## Guest: the host is deciding (PENDING received).
var awaiting_accept := false
## Host: the verified player waiting for accept/decline, or {}: {ip, port, name, nonce, seen}.
var pending := {}
## "123 456" once connected: both players see the same code unless someone is in the middle.
var security_code := ""
## Lag simulator for outgoing packets.
var lag_ms := 0
var jitter_ms := 0
var loss := 0.0
## Optional clock override (returns msec), so tests can run faster than real time.
var clock := Callable()
## Random per host session, so LanBrowser can merge replies that arrive by two routes.
var session_id := 0
## Lobby server mode (use_server()): the server's UDP address, "" otherwise.
var server_ip := ""
var server_port := 0
## The server has seen this socket (BOUND); public_endpoint is the address it saw.
var bound := false
var public_endpoint := ""

var _socket := PacketPeerUDP.new()
var _rng := RandomNumberGenerator.new()
var _crypto := Crypto.new()
var _secret := PackedByteArray() # cookie key, per peer
var _token := 0 # session token
var _nonce := 0 # guest: echoed by the host; host: the connecting guest's
var _cookie := 0 # guest: from CHALLENGE
var _last_answer := 0 # guest: last valid reply from the host
var _secure_started := 0
# Key exchange state.
var _public_pem := "" # host's public key as sent / received
var _host_nonce := PackedByteArray() # Nh
var _commitment := PackedByteArray()
var _guest_nonce := PackedByteArray() # Ng
var _key_secret := PackedByteArray()
var _key_cipher := PackedByteArray() # the KEY ciphertext (host: the one accepted)
var _last_key_sent := 0
var _send_enc := PackedByteArray()
var _send_mac := PackedByteArray()
var _send_iv := PackedByteArray()
var _recv_enc := PackedByteArray()
var _recv_mac := PackedByteArray()
var _recv_iv := PackedByteArray()
var _send_counter := 0
var _recv_highest := -1
var _recv_window := 0 # bit i set = counter (_recv_highest - i) seen
# Connection.
var _last_heard := 0
var _last_hello := -HELLO_INTERVAL_MS
var _last_ping := 0
var _rtt_samples := 0
var _next_seq := 1
var _unacked := {} # seq -> [type, payload, last sent msec]
var _next_in := 1
var _held := {} # out-of-order reliable messages: seq -> [type, payload]
var _delayed: Array[Array] = [] # lag simulator: [release msec, bytes]
var _declined := {} # ip -> msec until which its HELLOs are ignored
var _reply_window := -1000
var _unverified_replies := 0
var _verified_replies := 0
# Lobby server mode.
var _server_token := PackedByteArray() # 16 bytes, proves this socket to the server
var _relay_key := PackedByteArray() # 8 bytes, our key for RELAY
var _bind_role := 0 # 0 host, 1 guest
var _last_bind := -BIND_KEEPALIVE_MS
var _server_since := 0
var _candidates: Array[Dictionary] = [] # the peer's addresses: [{ip, port}]
var _punch_at := -1 # msec: when to start punching (host) / sending HELLOs (guest)
var _expected := {} # host: ip -> true for the matched peer's addresses (and RELAY_IP)


func _init(version: String = "", data_hash: int = 0, name: String = "Player") -> void:
	game_version = version
	content_hash = data_hash
	player_name = clean_name(name)
	_rng.randomize()
	session_id = _rng.randi()
	_secret = _crypto.generate_random_bytes(32)


## Starts making the host key in the background (about a second of CPU). Safe to call
## repeatedly; the online menu calls it on open so hosting never waits for it.
static func prepare_host_key() -> void:
	if _host_key != null or _host_key_task >= 0:
		return
	_host_key_task = WorkerThreadPool.add_task(func() -> void:
		_host_key = Crypto.new().generate_rsa(RSA_BITS))


## Waits for the key task and releases the key. Must run before the engine shuts down
## (Net does it in _exit_tree): quitting with the task never waited for, or with the key
## still held in a static variable, crashes on exit.
static func shutdown_host_key() -> void:
	if _host_key_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_host_key_task)
		_host_key_task = -1
	_host_key = null


static func host_key_ready() -> bool:
	if _host_key_task >= 0 and WorkerThreadPool.is_task_completed(_host_key_task):
		WorkerThreadPool.wait_for_task_completion(_host_key_task)
		_host_key_task = -1
	return _host_key != null and _host_key_task < 0


## Starts hosting on `port` (0 = any free port; see local_port()).
func host(port: int = DEFAULT_PORT) -> Error:
	close_socket()
	prepare_host_key()
	var err := _socket.bind(port, "*")
	if err != OK:
		return err
	is_host = true
	status = Status.HOSTING
	return OK


func join(ip: String, port: int = DEFAULT_PORT) -> Error:
	close_socket()
	var err := _socket.connect_to_host(ip, port)
	if err != OK:
		return err
	is_host = false
	remote_ip = ip
	remote_port = port
	status = Status.JOINING
	_nonce = _random_u64()
	_cookie = 0
	awaiting_accept = false
	_last_answer = _now()
	_last_hello = -HELLO_INTERVAL_MS
	return OK


## Guest through the lobby server: binds a socket (it hears the server and the host) and
## waits for the host's addresses (set_peer_candidates()). use_server() must follow.
func join_via_server() -> Error:
	close_socket()
	var err := _socket.bind(0, "*")
	if err != OK:
		return err
	is_host = false
	remote_ip = "" # unknown until a candidate answers (or the relay is used)
	remote_port = 0
	status = Status.JOINING
	_nonce = _random_u64()
	_cookie = 0
	awaiting_accept = false
	_last_answer = _now()
	_last_hello = -HELLO_INTERVAL_MS
	return OK


## Lobby server mode, after host() / join_via_server(): the server's UDP address and this
## player's credentials from its match_session. poll() BINDs from now on.
func use_server(ip: String, port: int, token: PackedByteArray, relay_key: PackedByteArray, as_host: bool) -> void:
	server_ip = ip
	server_port = port
	_server_token = token
	_relay_key = relay_key
	_bind_role = 0 if as_host else 1
	bound = false
	public_endpoint = ""
	_last_bind = -BIND_KEEPALIVE_MS
	_server_since = _now()
	_expected = {RELAY_IP: true} # the relay only forwards from the player we were matched with


## The peer's addresses from the server (peer_endpoints) and when to start using them:
## the host punches toward them, the guest sends its HELLO to each. Empty = relay only.
func set_peer_candidates(candidates: Array, start_in_ms: int) -> void:
	_candidates.clear()
	for c: Variant in candidates:
		if not c is Dictionary or _candidates.size() >= 8:
			continue
		var ip := str(c.get("ip", ""))
		var port := int(c.get("port", 0))
		if ip.is_valid_ip_address() and ip.count(".") == 3 and port > 0 and port < 65536:
			_candidates.append({ip = ip, port = port})
			if is_host:
				_expected[ip] = true
	_punch_at = _now() + clampi(start_in_ms, 0, 2000)


## How an internet connection runs: "direct" or "relay" ("" on a LAN).
func connection_path() -> String:
	if server_ip == "":
		return ""
	return "relay" if remote_ip == RELAY_IP else "direct"


func local_port() -> int:
	return _socket.get_local_port()


func is_connected_to_peer() -> bool:
	return status == Status.CONNECTED


## Host: let the pending player in.
func accept_join() -> void:
	if pending.is_empty() or status != Status.HOSTING:
		return
	remote_ip = pending.ip
	remote_port = pending.port
	remote_name = pending.name
	_nonce = pending.nonce
	pending = {}
	_start_securing()


## Host: turn the pending player away (and ignore that address for a while).
func decline_join() -> void:
	if pending.is_empty():
		return
	_declined[pending.ip] = _now() + DECLINE_BAN_MS
	_reply_to(pending.ip, pending.port, _reject(pending.nonce, "The host declined"), true)
	pending = {}


## Sends BYE (a few times, it's unreliable) and closes.
func close() -> void:
	if status == Status.CONNECTED:
		for i in 3:
			_send_now(_seal(T_BYE, PackedByteArray()))
	close_socket()
	status = Status.CLOSED


func close_socket() -> void:
	_socket.close()
	_unacked.clear()
	_held.clear()
	_delayed.clear()
	pending = {}
	_next_seq = 1
	_next_in = 1
	_token = 0
	rtt_ms = 0.0
	_rtt_samples = 0
	_key_cipher = PackedByteArray()
	_send_counter = 0
	_recv_highest = -1
	_recv_window = 0
	security_code = ""
	server_ip = ""
	server_port = 0
	bound = false
	_candidates.clear()
	_punch_at = -1
	_expected = {}


func send_input(bytes: PackedByteArray) -> void:
	if status == Status.CONNECTED:
		_send(_seal(T_INPUT, bytes))


func send_reliable(type: int, payload: PackedByteArray = PackedByteArray()) -> void:
	var seq := _next_seq
	_next_seq += 1
	_unacked[seq] = [type, payload, _now()]
	if status == Status.CONNECTED:
		_send(_reliable_datagram(seq, type, payload))


## Call often (every tick): sends due packets, reads the socket, runs timers.
func poll() -> void:
	if status == Status.IDLE or status == Status.CLOSED:
		return
	var now := _now()
	_flush_delayed(now)
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var ip := _socket.get_packet_ip()
		var port := _socket.get_packet_port()
		if bytes.is_empty():
			continue
		_receive(bytes, ip, port, now)
		if status == Status.CLOSED:
			return
	if server_ip != "" and now - _last_bind >= (BIND_KEEPALIVE_MS if bound else BIND_INTERVAL_MS):
		_last_bind = now
		_send_to(server_ip, server_port, _bind_datagram())
	match status:
		Status.HOSTING:
			if not pending.is_empty() and now - int(pending.seen) > CANDIDATE_TIMEOUT_MS:
				var gave_up: String = pending.name
				pending = {}
				join_cancelled.emit(gave_up)
			if _punch_at >= 0 and now >= _punch_at and now - _punch_at < PUNCH_TIMEOUT_MS and now - _last_hello >= PUNCH_INTERVAL_MS:
				_last_hello = now
				for c: Dictionary in _candidates:
					_send_to(c.ip, c.port, PackedByteArray([T_PUNCH]))
		Status.JOINING:
			if server_ip != "" and remote_ip == "":
				_find_path(now)
			elif now - _last_answer > JOIN_TIMEOUT_MS:
				_fail("No answer from the host through the server" if remote_ip == RELAY_IP else "No answer from %s:%d" % [remote_ip, remote_port])
			elif now - _last_hello >= HELLO_INTERVAL_MS:
				_last_hello = now
				_send_now(_hello())
		Status.SECURING:
			if now - _secure_started > SECURE_TIMEOUT_MS:
				if is_host:
					var gave_up := remote_name
					_back_to_hosting()
					join_cancelled.emit(gave_up)
				else:
					_fail("Couldn't secure the connection")
			elif is_host and _commitment.is_empty() and host_key_ready():
				_prepare_welcome()
				_send_now(_welcome())
			elif not is_host and now - _last_key_sent >= HELLO_INTERVAL_MS:
				_last_key_sent = now
				_send_now(_key_datagram())
		Status.CONNECTED:
			if now - _last_heard > timeout_ms:
				close_socket()
				status = Status.CLOSED
				disconnected.emit("Connection lost")
				return
			if now - _last_ping >= PING_INTERVAL_MS:
				_last_ping = now
				var ping := PackedByteArray()
				ping.resize(4)
				ping.encode_u32(0, now & 0xFFFFFFFF)
				_send(_seal(T_PING, ping))
			for seq: int in _unacked:
				var entry: Array = _unacked[seq]
				if now - entry[2] >= RESEND_INTERVAL_MS:
					entry[2] = now
					_send(_reliable_datagram(seq, entry[0], entry[1]))


# --- Receiving -------------------------------------------------------------------

func _receive(bytes: PackedByteArray, ip: String, port: int, now: int) -> void:
	var type := bytes[0]
	if server_ip != "" and type >= S_BIND and ip == server_ip and port == server_port:
		_on_server_datagram(bytes, now)
		return
	if type == T_DISCOVER:
		# LAN only: never answer the internet (an ANNOUNCE is bigger than the query).
		if is_host and server_ip == "" and status != Status.IDLE and status != Status.CLOSED and is_private_address(ip):
			_announce_to(bytes, ip, port)
		return
	if type == T_PUNCH:
		return
	if not is_host and not _socket.is_socket_connected():
		# A server-mode guest's socket hears everyone: only the host's address counts.
		if remote_ip == "":
			if not _is_candidate(ip, port):
				return
		elif ip != remote_ip or port != remote_port:
			return
	if is_host:
		if type == T_HELLO:
			_on_hello(bytes, ip, port, now)
			return
		if (status != Status.SECURING and status != Status.CONNECTED) or ip != remote_ip or port != remote_port:
			return
	elif status == Status.JOINING:
		_on_handshake_reply(bytes, now, ip, port)
		return
	if status != Status.SECURING and status != Status.CONNECTED:
		return
	if bytes.size() < 9 or bytes.decode_u64(1) != _token:
		return # no token, no entry (also a cheap filter before any cryptography)
	if type == T_KEY:
		if is_host:
			_on_key(bytes, now)
		return
	if type == T_KEYOK:
		if not is_host and status == Status.SECURING:
			_on_keyok(bytes, now)
		return
	if status != Status.CONNECTED:
		return
	var body: Variant = _open(bytes)
	if body == null:
		return # forged, corrupted or replayed
	_last_heard = now
	match type:
		T_INPUT:
			input_received.emit(body)
		T_PING:
			if body.size() >= 4:
				_send(_seal(T_PONG, body.slice(0, 4)))
		T_PONG:
			if body.size() >= 4:
				var sample := float((now & 0xFFFFFFFF) - body.decode_u32(0))
				if sample >= 0.0 and sample < 10000.0:
					_rtt_samples += 1
					rtt_ms = sample if _rtt_samples == 1 else lerpf(rtt_ms, sample, 0.2)
		T_RELIABLE:
			if body.size() < 5:
				return
			var seq: int = body.decode_u32(0)
			if seq >= _next_in + RELIABLE_WINDOW:
				return # too far ahead: not acknowledged, the sender resends later
			_send(_seal(T_ACK, body.slice(0, 4)))
			if seq >= _next_in and not _held.has(seq):
				_held[seq] = [body[4], body.slice(5)]
			while _held.has(_next_in):
				var msg: Array = _held[_next_in]
				_held.erase(_next_in)
				_next_in += 1
				message_received.emit(msg[0], msg[1])
				if status != Status.CONNECTED:
					return
		T_ACK:
			if body.size() >= 4:
				_unacked.erase(body.decode_u32(0))
		T_BYE:
			close_socket()
			status = Status.CLOSED
			disconnected.emit("Your opponent left")


## Host: HELLO → CHALLENGE, or (with a valid cookie) the real answer.
func _on_hello(bytes: PackedByteArray, ip: String, port: int, now: int) -> void:
	if server_ip != "" and not _expected.has(ip):
		return # an internet game: only the player the server matched us with
	var hello := _parse_hello(bytes)
	if hello.is_empty():
		return
	if (status == Status.SECURING or status == Status.CONNECTED) and ip == remote_ip and port == remote_port:
		if hello.nonce == _nonce and not _commitment.is_empty():
			_send_now(_welcome()) # our WELCOME was lost: say it again
		return
	if _declined.get(ip, 0) > now:
		return
	if hello.cookie != _cookie_for(ip, port, now) and hello.cookie != _cookie_for(ip, port, now - COOKIE_WINDOW_MS):
		var challenge := PackedByteArray([T_CHALLENGE])
		challenge.resize(17)
		challenge.encode_u64(1, hello.nonce)
		challenge.encode_u64(9, _cookie_for(ip, port, now))
		_reply_to(ip, port, challenge, false)
		return
	# The address is proven from here on.
	var problem := ""
	if hello.protocol != PROTOCOL or hello.version != game_version:
		problem = "Different game version (host %s, you %s)" % [game_version, hello.version]
	elif hello.data_hash != (content_hash & 0xFFFFFFFF):
		problem = "Different game data: both players need the same build"
	elif status == Status.SECURING or status == Status.CONNECTED:
		problem = "The host is already in a match"
	elif not pending.is_empty() and (pending.ip != ip or pending.port != port):
		problem = "The host is busy with another player"
	if problem != "":
		_reply_to(ip, port, _reject(hello.nonce, problem), true)
		return
	if auto_accept or server_ip != "": # the server already asked the host
		remote_ip = ip
		remote_port = port
		remote_name = hello.name
		_nonce = hello.nonce
		_start_securing()
		return
	var is_new := pending.is_empty()
	pending = {ip = ip, port = port, name = hello.name, nonce = hello.nonce, seen = now}
	var waiting := PackedByteArray([T_PENDING])
	waiting.resize(9)
	waiting.encode_u64(1, hello.nonce)
	waiting.append_array(_string_bytes(player_name))
	_reply_to(ip, port, waiting, true)
	if is_new:
		join_requested.emit(hello.name)


## Guest: CHALLENGE / PENDING / WELCOME / REJECT, each only with our nonce.
func _on_handshake_reply(bytes: PackedByteArray, now: int, ip: String, port: int) -> void:
	if bytes.size() < 9 or bytes.decode_u64(1) != _nonce:
		return
	if remote_ip == "": # server mode: the first candidate to answer is the way through
		remote_ip = ip
		remote_port = port
	match bytes[0]:
		T_CHALLENGE:
			if bytes.size() < 17:
				return
			_last_answer = now
			_cookie = bytes.decode_u64(9)
			_last_hello = now
			_send_now(_hello())
		T_PENDING:
			var name: Variant = read_string_at(bytes, 9)
			_last_answer = now
			if not awaiting_accept:
				awaiting_accept = true
				join_pending.emit(clean_name(name) if name != null else "the host")
		T_WELCOME:
			_on_welcome(bytes, now)
		T_REJECT:
			var reason: Variant = read_string_at(bytes, 9)
			_fail(reason if reason != null else "The host refused the connection")


## Guest: the host's key and commitment. Answer with our encrypted secret.
func _on_welcome(bytes: PackedByteArray, now: int) -> void:
	if bytes.size() < 17:
		return
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(17)
	var name: Variant = read_string(buffer)
	var pem: Variant = read_string(buffer, 2048)
	if name == null or pem == null or buffer.get_available_bytes() != 32:
		return
	var public_key := CryptoKey.new()
	if public_key.load_from_string(pem, true) != OK:
		_fail("The host sent an invalid key")
		return
	_token = bytes.decode_u64(9)
	remote_name = clean_name(name)
	_public_pem = pem
	_commitment = buffer.get_data(32)[1]
	_key_secret = _crypto.generate_random_bytes(32)
	_guest_nonce = _crypto.generate_random_bytes(16)
	_key_cipher = _crypto.encrypt(public_key, _key_secret)
	if _key_cipher.is_empty():
		_fail("Couldn't secure the connection")
		return
	status = Status.SECURING
	awaiting_accept = false
	_secure_started = now
	_last_key_sent = now
	_send_now(_key_datagram())


## Host: the guest's encrypted secret. Only the first one is ever decrypted.
func _on_key(bytes: PackedByteArray, now: int) -> void:
	if bytes.size() != 9 + 2 + KEY_CIPHER_SIZE + 16:
		return
	var cipher := bytes.slice(11, 11 + KEY_CIPHER_SIZE)
	if not _key_cipher.is_empty():
		if cipher == _key_cipher and status == Status.CONNECTED:
			_send_now(_keyok_datagram()) # our KEYOK was lost
		return
	if status != Status.SECURING or _commitment.is_empty():
		return
	_key_cipher = cipher
	var secret := _crypto.decrypt(_host_key, cipher)
	if secret.size() != 32:
		return # not a key for us; the exchange will time out
	_key_secret = secret
	_guest_nonce = bytes.slice(11 + KEY_CIPHER_SIZE)
	_finish_keys()
	_send_now(_keyok_datagram())
	_connected(now)


## Guest: the host's nonce must match its commitment.
func _on_keyok(bytes: PackedByteArray, now: int) -> void:
	if bytes.size() != 9 + 16:
		return
	var nonce := bytes.slice(9)
	if _sha256([("3DF-commit|" + _public_pem).to_utf8_buffer(), nonce]) != _commitment:
		_fail("The connection's security check failed")
		return
	_host_nonce = nonce
	_finish_keys()
	_connected(now)


func _start_securing() -> void:
	status = Status.SECURING
	_secure_started = _now()
	_token = _random_u64()
	_commitment = PackedByteArray()
	_key_cipher = PackedByteArray()
	if host_key_ready():
		_prepare_welcome()
		_send_now(_welcome())
	# else poll() sends WELCOME as soon as the background key is ready


func _prepare_welcome() -> void:
	_public_pem = _host_key.save_to_string(true)
	_host_nonce = _crypto.generate_random_bytes(16)
	_commitment = _sha256([("3DF-commit|" + _public_pem).to_utf8_buffer(), _host_nonce])


func _back_to_hosting() -> void:
	status = Status.HOSTING
	_token = 0
	_commitment = PackedByteArray()
	_key_cipher = PackedByteArray()


func _connected(now: int) -> void:
	status = Status.CONNECTED
	awaiting_accept = false
	_last_heard = now
	connected.emit()
	for seq: int in _unacked: # anything queued before the connection
		_send(_reliable_datagram(seq, _unacked[seq][0], _unacked[seq][1]))


func _fail(reason: String) -> void:
	close_socket()
	status = Status.CLOSED
	connect_failed.emit(reason)


## Session keys from the secret and both nonces; the security code from everything.
func _finish_keys() -> void:
	var salt := _host_nonce + _guest_nonce
	var master := _crypto.hmac_digest(HashingContext.HASH_SHA256, _key_secret, "3DF-keys|".to_utf8_buffer() + salt)
	var to_guest := ["enc|h2g", "mac|h2g", "iv|h2g"].map(func(label: String) -> PackedByteArray:
		return _crypto.hmac_digest(HashingContext.HASH_SHA256, master, label.to_utf8_buffer()))
	var to_host := ["enc|g2h", "mac|g2h", "iv|g2h"].map(func(label: String) -> PackedByteArray:
		return _crypto.hmac_digest(HashingContext.HASH_SHA256, master, label.to_utf8_buffer()))
	var mine: Array = to_guest if is_host else to_host
	var theirs: Array = to_host if is_host else to_guest
	_send_enc = mine[0]
	_send_mac = mine[1]
	_send_iv = mine[2]
	_recv_enc = theirs[0]
	_recv_mac = theirs[1]
	_recv_iv = theirs[2]
	_send_counter = 0
	_recv_highest = -1
	_recv_window = 0
	var digest := _sha256([("3DF-code|" + _public_pem).to_utf8_buffer(), _key_cipher, _host_nonce, _guest_nonce])
	var code := digest.decode_u32(0) % 1000000
	security_code = "%03d %03d" % [floori(code / 1000.0), code % 1000]


# --- Sealed (encrypted + authenticated) datagrams --------------------------------

func _seal(type: int, body: PackedByteArray) -> PackedByteArray:
	var counter := _send_counter
	_send_counter += 1
	var header := PackedByteArray([type])
	header.resize(SEALED_HEADER)
	header.encode_u64(1, _token)
	header.encode_u64(9, counter)
	var padded := body.duplicate()
	var pad := 16 - padded.size() % 16
	for i in pad:
		padded.append(pad)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, _send_enc, _iv_for(_send_iv, counter))
	var cipher := aes.update(padded)
	aes.finish()
	var out := header + cipher
	out.append_array(_crypto.hmac_digest(HashingContext.HASH_SHA256, _send_mac, out).slice(0, TAG_SIZE))
	return out


## The body of a sealed datagram, or null if it's forged, corrupted or a replay.
func _open(bytes: PackedByteArray) -> Variant:
	var cipher_size := bytes.size() - SEALED_HEADER - TAG_SIZE
	if cipher_size < 16 or cipher_size % 16 != 0:
		return null
	var signed := bytes.slice(0, bytes.size() - TAG_SIZE)
	var tag := _crypto.hmac_digest(HashingContext.HASH_SHA256, _recv_mac, signed).slice(0, TAG_SIZE)
	if not _crypto.constant_time_compare(tag, bytes.slice(bytes.size() - TAG_SIZE)):
		return null
	var counter := bytes.decode_u64(9)
	if counter < 0 or not _replay_check(counter):
		return null
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, _recv_enc, _iv_for(_recv_iv, counter))
	var plain := aes.update(bytes.slice(SEALED_HEADER, SEALED_HEADER + cipher_size))
	aes.finish()
	var pad := plain[plain.size() - 1]
	if pad < 1 or pad > 16:
		return null
	return plain.slice(0, plain.size() - pad)


## Accepts each counter once, within REPLAY_WINDOW of the newest seen.
func _replay_check(counter: int) -> bool:
	if counter > _recv_highest:
		var shift := counter - _recv_highest
		_recv_window = 1 if shift >= REPLAY_WINDOW else (_recv_window << shift) | 1
		_recv_highest = counter
		return true
	var age := _recv_highest - counter
	if age >= REPLAY_WINDOW or (_recv_window >> age) & 1:
		return false
	_recv_window |= 1 << age
	return true


func _iv_for(key: PackedByteArray, counter: int) -> PackedByteArray:
	var counter_bytes := PackedByteArray()
	counter_bytes.resize(8)
	counter_bytes.encode_u64(0, counter)
	return _crypto.hmac_digest(HashingContext.HASH_SHA256, key, counter_bytes).slice(0, 16)


func _sha256(parts: Array) -> PackedByteArray:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for part: PackedByteArray in parts:
		hashing.update(part)
	return hashing.finish()


# --- Sending ---------------------------------------------------------------------

func _send(bytes: PackedByteArray) -> void:
	if loss > 0.0 and _rng.randf() < loss:
		return
	if lag_ms <= 0 and jitter_ms <= 0:
		_send_now(bytes)
		return
	var release := _now() + lag_ms + (_rng.randi_range(0, jitter_ms) if jitter_ms > 0 else 0)
	_delayed.append([release, bytes])


func _flush_delayed(now: int) -> void:
	if _delayed.is_empty():
		return
	var still: Array[Array] = []
	for entry in _delayed:
		if entry[0] <= now:
			_send_now(entry[1])
		else:
			still.append(entry)
	_delayed = still


func _send_now(bytes: PackedByteArray) -> void:
	_send_to(remote_ip, remote_port, bytes)


## Sends one datagram: through the server's relay for RELAY_IP, else straight there.
func _send_to(ip: String, port: int, bytes: PackedByteArray) -> void:
	if ip == RELAY_IP:
		if server_ip == "" or bytes.size() > MAX_RELAY_PAYLOAD:
			return
		var wrapped := PackedByteArray([S_RELAY])
		wrapped.append_array(_relay_key)
		wrapped.append_array(bytes)
		bytes = wrapped
		ip = server_ip
		port = server_port
	if _socket.is_socket_connected():
		_socket.put_packet(bytes) # a LAN guest's socket only talks to the host
		return
	if ip == "":
		return
	_socket.set_dest_address(ip, port)
	_socket.put_packet(bytes)


## Guest in server mode, before any candidate answered: HELLOs to every candidate after
## the agreed start; none answering in PUNCH_TIMEOUT_MS (or none at all) = the relay.
func _find_path(now: int) -> void:
	if _punch_at < 0:
		if now - _server_since > ENDPOINTS_TIMEOUT_MS:
			_fail("The server couldn't connect you to the host")
		return
	if now < _punch_at:
		return
	if _candidates.is_empty() or now - _punch_at >= PUNCH_TIMEOUT_MS:
		remote_ip = RELAY_IP
		remote_port = 0
		_cookie = 0
		_last_answer = now
		_last_hello = -HELLO_INTERVAL_MS
		return
	if now - _last_hello >= PUNCH_INTERVAL_MS:
		_last_hello = now
		var hello := _hello()
		for c: Dictionary in _candidates:
			_send_to(c.ip, c.port, hello)


func _is_candidate(ip: String, port: int) -> bool:
	for c: Dictionary in _candidates:
		if c.ip == ip and c.port == port:
			return true
	return false


## BOUND (the address the server saw) and RELAYED (a datagram from the peer).
func _on_server_datagram(bytes: PackedByteArray, now: int) -> void:
	match bytes[0]:
		S_BOUND:
			if bytes.size() == 7:
				bound = true
				public_endpoint = "%d.%d.%d.%d:%d" % [bytes[1], bytes[2], bytes[3], bytes[4], bytes.decode_u16(5)]
		S_RELAYED:
			if bytes.size() >= 2 and bytes[1] < S_BIND:
				_receive(bytes.slice(1), RELAY_IP, 0, now)


## [BIND][session token 16][role][n][n × (ipv4, u16 port)]: this socket's LAN addresses,
## which the server passes on when both players are behind the same public address.
func _bind_datagram() -> PackedByteArray:
	var out := PackedByteArray([S_BIND])
	out.append_array(_server_token)
	out.append(_bind_role)
	var locals := local_candidates(local_port())
	out.append(locals.size())
	for c: Dictionary in locals:
		for part in (c.ip as String).split("."):
			out.append(int(part))
		var port_bytes := PackedByteArray()
		port_bytes.resize(2)
		port_bytes.encode_u16(0, c.port)
		out.append_array(port_bytes)
	return out


## This machine's private IPv4 addresses with `port` (at most MAX_BIND_CANDIDATES).
static func local_candidates(port: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and is_private_address(address) and not address.begins_with("127.") \
				and not address.begins_with("169.254."):
			out.append({ip = address, port = port})
			if out.size() >= MAX_BIND_CANDIDATES:
				break
	return out


## Host: a reply to some address other than the connected guest, under the rate limits.
func _reply_to(ip: String, port: int, bytes: PackedByteArray, verified: bool) -> void:
	var now := _now()
	if now - _reply_window >= 1000:
		_reply_window = now
		_unverified_replies = 0
		_verified_replies = 0
	if verified:
		if _verified_replies >= MAX_VERIFIED_REPLIES:
			return
		_verified_replies += 1
	else:
		if _unverified_replies >= MAX_UNVERIFIED_REPLIES:
			return
		_unverified_replies += 1
	_send_to(ip, port, bytes)


## Key exchange datagrams: [type][session token][body], not encrypted.
func _framed(type: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([type])
	out.resize(9)
	out.encode_u64(1, _token)
	out.append_array(body)
	return out


func _key_datagram() -> PackedByteArray:
	var body := PackedByteArray()
	body.resize(2)
	body.encode_u16(0, _key_cipher.size())
	body.append_array(_key_cipher)
	body.append_array(_guest_nonce)
	return _framed(T_KEY, body)


func _keyok_datagram() -> PackedByteArray:
	return _framed(T_KEYOK, _host_nonce)


func _reliable_datagram(seq: int, type: int, payload: PackedByteArray) -> PackedByteArray:
	var body := PackedByteArray()
	body.resize(5)
	body.encode_u32(0, seq)
	body[4] = type
	body.append_array(payload)
	return _seal(T_RELIABLE, body)


func _hello() -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(T_HELLO)
	out.put_u16(PROTOCOL)
	out.put_utf8_string(game_version)
	out.put_u32(content_hash & 0xFFFFFFFF)
	out.put_utf8_string(player_name)
	out.put_u64(_nonce)
	out.put_u64(_cookie)
	return out.data_array


## {protocol, version, data_hash, name, nonce, cookie}, or {} when malformed.
func _parse_hello(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 31:
		return {}
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(1)
	var protocol := buffer.get_u16()
	var version: Variant = read_string(buffer, 64)
	if version == null or buffer.get_available_bytes() < 4:
		return {}
	var data_hash := buffer.get_u32()
	var name: Variant = read_string(buffer)
	if name == null or buffer.get_available_bytes() < 16:
		return {}
	return {protocol = protocol, version = version, data_hash = data_hash, name = clean_name(name),
		nonce = buffer.get_u64(), cookie = buffer.get_u64()}


## [WELCOME][nonce][token][name][public key PEM][commitment 32]
func _welcome() -> PackedByteArray:
	var out := PackedByteArray([T_WELCOME])
	out.resize(17)
	out.encode_u64(1, _nonce)
	out.encode_u64(9, _token)
	out.append_array(_string_bytes(player_name))
	out.append_array(_string_bytes(_public_pem))
	out.append_array(_commitment)
	return out


func _reject(nonce: int, reason: String) -> PackedByteArray:
	var out := PackedByteArray([T_REJECT])
	out.resize(9)
	out.encode_u64(1, nonce)
	out.append_array(_string_bytes(reason))
	return out


## LAN discovery reply: [ANNOUNCE, echoed query time u32, protocol u16, version, data hash
## u32, session u32, status u8 (0 waiting, 1 busy), game port u16, name].
func _announce_to(query: PackedByteArray, ip: String, port: int) -> void:
	if query.size() < 5:
		return
	var out := StreamPeerBuffer.new()
	out.put_u8(T_ANNOUNCE)
	out.put_u32(query.decode_u32(1))
	out.put_u16(PROTOCOL)
	out.put_utf8_string(game_version)
	out.put_u32(content_hash & 0xFFFFFFFF)
	out.put_u32(session_id)
	out.put_u8(0 if status == Status.HOSTING and pending.is_empty() else 1)
	out.put_u16(local_port())
	out.put_utf8_string(player_name)
	_reply_to(ip, port, out.data_array, false)


## The cookie for an address in the time window containing `time`: the first 8 bytes of
## HMAC-SHA256(secret, ip|port|window). Never 0 (0 means "no cookie yet").
func _cookie_for(ip: String, port: int, time: int) -> int:
	var message := ("%s|%d|%d" % [ip, port, floori(time / float(COOKIE_WINDOW_MS))]).to_utf8_buffer()
	var digest := _crypto.hmac_digest(HashingContext.HASH_SHA256, _secret, message)
	return maxi(digest.decode_u64(0) & 0x7FFFFFFFFFFFFFFF, 1)


func _random_u64() -> int:
	return maxi(_crypto.generate_random_bytes(8).decode_u64(0) & 0x7FFFFFFFFFFFFFFF, 1)


func _string_bytes(text: String) -> PackedByteArray:
	var utf8 := text.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, utf8.size())
	out.append_array(utf8)
	return out


func _now() -> int:
	return clock.call() if clock.is_valid() else Time.get_ticks_msec()


# --- Helpers ---------------------------------------------------------------------

## Reads a put_utf8_string() value, or null when the datagram is too short or the length
## is implausible (malformed or hostile packets must not make the engine log errors).
static func read_string(buffer: StreamPeerBuffer, max_bytes: int = 256) -> Variant:
	if buffer.get_available_bytes() < 4:
		return null
	var length := buffer.get_u32()
	if length > max_bytes or length > buffer.get_available_bytes():
		return null
	var data: PackedByteArray = buffer.get_data(length)[1]
	return data.get_string_from_utf8()


## read_string() at a byte offset of a datagram.
static func read_string_at(bytes: PackedByteArray, offset: int, max_bytes: int = 256) -> Variant:
	if bytes.size() < offset + 4:
		return null
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(offset)
	return read_string(buffer, max_bytes)


## A display-safe player name: no control, zero-width or bidirectional-override
## characters (they can disguise names in lists and the HUD), trimmed, MAX_NAME long.
static func clean_name(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 32 or (c >= 0x7F and c <= 0x9F) or (c >= 0x200B and c <= 0x200F) or (c >= 0x2028 and c <= 0x202E) \
				or (c >= 0x2060 and c <= 0x206F) or c == 0xFEFF:
			continue
		out += text[i]
	out = out.strip_edges().left(MAX_NAME)
	return out if out != "" else "Player"


## Loopback, link-local and the private IPv4 ranges (10/8, 172.16/12, 192.168/16).
static func is_private_address(ip: String) -> bool:
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	var a := int(parts[0])
	var b := int(parts[1])
	return a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254)
