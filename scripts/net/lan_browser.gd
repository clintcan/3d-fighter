class_name LanBrowser
extends RefCounted
## Finds games hosted on the local network. Every QUERY_INTERVAL_MS it sends a DISCOVER
## datagram to the game port on the broadcast address, each local /24 subnet's broadcast
## address (Windows sends 255.255.255.255 out of one adapter only) and this machine;
## hosts reply directly with ANNOUNCE (NetPeer._announce_to). Hosts that stop replying
## drop off the list after EXPIRE_MS. Driven by poll(), like NetPeer.
## Only replies that echo one of our recent queries count (no unsolicited entries), the
## list holds at most MAX_GAMES, and names are cleaned (NetPeer.clean_name).

signal games_changed

const QUERY_INTERVAL_MS := 1000
const EXPIRE_MS := 3500
const MAX_GAMES := 32
const RECENT_QUERIES := 4 # replies must echo one of these query times

## Ports to query (the game port; tests use the port their host bound).
var ports: Array[int] = [NetPeer.DEFAULT_PORT]
var game_version := ""
var content_hash := 0
## Optional clock override (msec), like NetPeer.clock.
var clock := Callable()
## Found games, keyed by host session id: {id, name, ip, port, status, ping_ms, compatible,
## version, last_seen}.
var games := {}

var _socket := PacketPeerUDP.new()
var _targets := PackedStringArray()
var _last_query := -QUERY_INTERVAL_MS
var _recent_queries: Array[int] = []
var _started := false


func _init(version: String = "", data_hash: int = 0) -> void:
	game_version = version
	content_hash = data_hash


func start() -> Error:
	stop()
	_socket.set_broadcast_enabled(true)
	var err := _socket.bind(0)
	if err != OK:
		return err
	_targets = broadcast_targets()
	_started = true
	_last_query = -QUERY_INTERVAL_MS
	return OK


func stop() -> void:
	_socket.close()
	_started = false
	if not games.is_empty():
		games.clear()
		games_changed.emit()


func is_running() -> bool:
	return _started


## Sorted for display: joinable games first, then by name.
func sorted_games() -> Array:
	var list := games.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_open: bool = a.compatible and a.status == 0
		var b_open: bool = b.compatible and b.status == 0
		if a_open != b_open:
			return a_open
		return String(a.name).naturalnocasecmp_to(b.name) < 0)
	return list


func poll() -> void:
	if not _started:
		return
	var now := _now()
	if now - _last_query >= QUERY_INTERVAL_MS:
		_last_query = now
		_query(now)
	var changed := false
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		var ip := _socket.get_packet_ip()
		if bytes.size() >= 16 and bytes[0] == NetPeer.T_ANNOUNCE:
			changed = _on_announce(bytes, ip, now) or changed
	for id: int in games.keys():
		if now - int(games[id].last_seen) > EXPIRE_MS:
			games.erase(id)
			changed = true
	if changed:
		games_changed.emit()


## 255.255.255.255, each local IPv4's /24 broadcast address, and localhost.
static func broadcast_targets() -> PackedStringArray:
	var out := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for address in IP.get_local_addresses():
		var parts := address.split(".")
		if parts.size() != 4 or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		var broadcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if broadcast not in out:
			out.append(broadcast)
	return out


func _query(now: int) -> void:
	# Two queries can't share a time stamp, or the echo check couldn't tell them apart.
	var stamp := now & 0xFFFFFFFF
	if not _recent_queries.is_empty() and stamp == _recent_queries[-1]:
		return
	_recent_queries.append(stamp)
	if _recent_queries.size() > RECENT_QUERIES:
		_recent_queries.pop_front()
	var query := StreamPeerBuffer.new()
	query.put_u8(NetPeer.T_DISCOVER)
	query.put_u32(stamp)
	for target in _targets:
		for port in ports:
			_socket.set_dest_address(target, port)
			_socket.put_packet(query.data_array)


func _on_announce(bytes: PackedByteArray, ip: String, now: int) -> bool:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(1)
	var sent := buffer.get_u32()
	if sent not in _recent_queries:
		return false # not an answer to us
	var protocol := buffer.get_u16()
	var read_version: Variant = NetPeer.read_string(buffer)
	if read_version == null or buffer.get_available_bytes() < 11:
		return false # malformed
	var version: String = read_version
	var data_hash := buffer.get_u32()
	var id := buffer.get_u32()
	var status := buffer.get_u8()
	var port := buffer.get_u16()
	var read_name: Variant = NetPeer.read_string(buffer)
	if read_name == null:
		return false
	var name := NetPeer.clean_name(read_name)
	var ping := clampi((now & 0xFFFFFFFF) - sent, 0, 9999)
	var known: Dictionary = games.get(id, {})
	if known.is_empty() and games.size() >= MAX_GAMES:
		return false
	# The same host can answer on several routes (loopback and LAN); keep a LAN address.
	if not known.is_empty() and ip.begins_with("127.") and not String(known.ip).begins_with("127."):
		ip = known.ip
	var entry := {id = id, name = name, ip = ip, port = port, status = status,
		ping_ms = mini(ping, int(known.get("ping_ms", ping))) if known.get("last_query", -1) == sent else ping,
		compatible = protocol == NetPeer.PROTOCOL and version == game_version and data_hash == (content_hash & 0xFFFFFFFF),
		version = version, last_seen = now, last_query = sent}
	var changed: bool = known.is_empty() or known.status != status or known.name != entry.name or known.ip != ip \
		or absi(int(known.ping_ms) - int(entry.ping_ms)) >= 5
	games[id] = entry
	return changed


func _now() -> int:
	return clock.call() if clock.is_valid() else Time.get_ticks_msec()
