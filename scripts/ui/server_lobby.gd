extends Control
## Internet lobby: connect to a lobby server, browse its rooms, open one, join one (by the
## list or by its code) or watch a match in one.
## The server address comes filled in: the official one from SERVER_LIST_URL (a file in the
## game's repository, so the server can move without a game update), else DEFAULT_SERVER.
## Players can type their own; only an address that differs from the official one is saved,
## so everyone else follows the list when the server moves. When the server matches two players the
## Net autoload connects them (directly or through the server's relay) and both go on to
## character select, as on a LAN. Spectators go straight to the fight they watch.

const ONLINE_MENU_SCENE := "res://scenes/online_menu.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const WALLPAPER := "res://assets/ui/wallpaper.png"
const GOLD := Color(1.0, 0.82, 0.3)
const DIM := Color(0.72, 0.75, 0.82)
const BAD := Color(1.0, 0.55, 0.45)
const LIST_ROWS := 6
const REFRESH_MS := 3000
const DEFAULT_SERVER := "wss://104-248-147-130.sslip.io/v1/ws"
const SERVER_LIST_URL := "https://raw.githubusercontent.com/clintcan/3d-fighter/main/online/servers.json"

var _name_edit: LineEdit
var _url_edit: LineEdit
var _connect_button: Button
var _relay_check: CheckBox
var _list: VBoxContainer
var _list_empty: Label
## "23 online · 6 in matches" beside the ROOMS heading (the server's `online` object).
var _online: Label
var _rows := {} # room id -> HBoxContainer
var _password_edit: LineEdit
var _spectators_check: CheckBox
var _listed_check: CheckBox
var _create_button: Button
var _code_edit: LineEdit
var _join_code_button: Button
var _watch_code_button: Button
var _back_button: Button
var _status: Label
var _join_prompt: HBoxContainer
var _accept_button: Button
var _request_id := ""
var _last_refresh := -REFRESH_MS
var _connecting := false
## The official server address (DEFAULT_SERVER until the list says otherwise).
var _official := DEFAULT_SERVER
var _list_request: HTTPRequest


func _ready() -> void:
	Audio.music(&"menu")
	_build()
	Net.server_connected.connect(_on_server_connected)
	Net.server_closed.connect(_on_server_closed)
	Net.server_message.connect(_on_message)
	Net.connected.connect(_on_peer_connected)
	Net.connect_failed.connect(_on_peer_failed)
	Net.spectate_closed.connect(_on_spectate_closed)
	NetPeer.prepare_host_key()
	_fetch_server_list()
	if Net.last_reason != "":
		_set_status(Net.last_reason, BAD)
		Net.last_reason = ""
	_update_controls()
	if Net.is_server_open():
		Net.list_rooms()
	_connect_button.grab_focus()


func _exit_tree() -> void:
	Net.server_connected.disconnect(_on_server_connected)
	Net.server_closed.disconnect(_on_server_closed)
	Net.server_message.disconnect(_on_message)
	Net.connected.disconnect(_on_peer_connected)
	Net.connect_failed.disconnect(_on_peer_failed)
	Net.spectate_closed.disconnect(_on_spectate_closed)


func _process(_delta: float) -> void:
	# A waiting host keeps refreshing too: the list is hidden, but the online count stays current.
	if Net.is_server_open() and Net.room_role in ["", "host"] and Time.get_ticks_msec() - _last_refresh >= REFRESH_MS:
		_last_refresh = Time.get_ticks_msec()
		Net.list_rooms()


# --- Actions ---------------------------------------------------------------------

func _toggle_connection() -> void:
	if Net.is_server_open() or _connecting:
		Net.disconnect_server()
		_connecting = false
		_clear_rows()
		_show_online(null)
		_set_status("Disconnected.", DIM)
		_update_controls()
		return
	var url := _url_edit.text.strip_edges()
	if url == "":
		_set_status("Type the server's address first, for example ws://lobby.example.com:8080/v1/ws", BAD)
		_url_edit.grab_focus()
		return
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://" + url
	if not url.contains("/v1/ws"):
		url = url.trim_suffix("/") + "/v1/ws"
	_url_edit.text = url
	Settings.server_url = url if url != _official else "" # the official one follows the list
	Settings.player_name = _name_edit.text.strip_edges().left(24)
	Settings.relay_only = _relay_check.button_pressed
	Settings.save_settings()
	var err := Net.connect_server(url)
	if err != OK:
		_set_status("Can't connect to \"%s\" (%s)." % [url, error_string(err)], BAD)
		return
	_connecting = true
	_set_status("Connecting to %s..." % url, DIM)
	_update_controls()


func _create_room() -> void:
	Net.create_room("", _listed_check.button_pressed, _password_edit.text.strip_edges(), _spectators_check.button_pressed)
	_set_status("Opening a room...", DIM)


func _join(room_key: String) -> void:
	if room_key.strip_edges() == "":
		_set_status("Type a room code first.", BAD)
		_code_edit.grab_focus()
		return
	Net.join_room(room_key, _password_edit.text.strip_edges())
	_set_status("Asking to join...", DIM)
	_update_controls()


func _watch(room_key: String) -> void:
	if room_key.strip_edges() == "":
		_set_status("Type a room code first.", BAD)
		_code_edit.grab_focus()
		return
	Net.spectate_room(room_key, _password_edit.text.strip_edges())
	_set_status("Joining as a spectator...", DIM)


func _back() -> void:
	Audio.sfx(&"ui_back", -4.0)
	match Net.room_role:
		"pending":
			Net.cancel_join()
			_set_status("Cancelled.", DIM)
		"host", "guest", "spectator":
			Net.leave()
			Net.leave_room()
			_join_prompt.visible = false
			_set_status("Left the room.", DIM)
		_:
			Net.disconnect_server()
			get_tree().change_scene_to_file(ONLINE_MENU_SCENE)
			return
	_update_controls()
	_back_button.grab_focus()


func _answer(accept: bool) -> void:
	_join_prompt.visible = false
	Net.answer_join(_request_id, accept)
	_set_status("Connecting..." if accept else "Declined. Still waiting for an opponent...", DIM)
	_back_button.grab_focus()


# --- Server events ---------------------------------------------------------------

func _on_server_connected() -> void:
	_connecting = false
	var welcome := Net.lobby.welcome
	var text := "Connected to the %s server." % str(welcome.get("region", "lobby")).to_upper()
	if welcome.has("motd"):
		text += "\n" + str(welcome.motd)
	if welcome.has("latest_game_version"):
		text += "\nVersion %s is out: %s" % [welcome.latest_game_version, welcome.get("update_url", "")]
	_set_status(text, GOLD)
	_show_online(welcome.get("online"))
	_update_controls()
	Net.list_rooms()


func _on_server_closed(reason: String) -> void:
	_connecting = false
	_join_prompt.visible = false
	_clear_rows()
	_show_online(null)
	_set_status(reason, BAD)
	_update_controls()


func _on_message(msg: Dictionary) -> void:
	match str(msg.type):
		"rooms":
			_show_online(msg.get("online"))
			_show_rooms(msg.get("rooms", []))
		"room_created":
			_clear_rows()
			_set_status("Your room is open: code %s\nWaiting for an opponent... Give friends the code, or wait for someone from the list." % msg.get("code", ""), GOLD)
			_update_controls()
		"join_request":
			_request_id = str(msg.get("request_id", ""))
			Audio.sfx(&"ui_accept", -4.0)
			_set_status("%s wants to join your room." % NetPeer.clean_name(str(msg.get("name", ""))), GOLD)
			_join_prompt.visible = true
			_accept_button.grab_focus()
		"join_cancelled":
			_join_prompt.visible = false
			_set_status("They stopped asking. Still waiting for an opponent... (code %s)" % Net.room_code, DIM)
		"join_pending":
			_set_status("Waiting for the host to accept...", DIM)
		"join_declined":
			var why := str(msg.get("reason", "declined"))
			_set_status("The host declined." if why == "declined" else "No answer from the host." if why == "timeout" else "Couldn't join (%s)." % why, BAD)
			_update_controls()
		"match_session":
			_join_prompt.visible = false
			_set_status("Connecting to %s..." % NetPeer.clean_name(str(msg.get("peer", {}).get("name", "your opponent"))), DIM)
			_update_controls()
		"player_left":
			if Net.room_role == "host":
				_set_status("Your opponent left. Still waiting... (code %s)" % Net.room_code, DIM)
			elif str(msg.get("reason", "")) == "kicked":
				_set_status("The host removed you from the room.", BAD)
			_update_controls()
		"room_closed":
			_set_status("The room closed.", BAD)
			_update_controls()
		"spectate_started":
			_set_status("Watching. %s" % ("Loading the match..." if msg.get("match_live", false) else "Waiting for the next match to start..."), GOLD)
			_update_controls()
		"server_notice":
			_set_status(str(msg.get("message", "")), GOLD if msg.get("severity") == "info" else BAD)
		"error":
			_set_status(LobbyClient.error_text(msg), BAD)
			_update_controls()


func _on_peer_connected() -> void:
	if Net.peer == null or Net.peer.server_ip == "":
		return
	Audio.sfx(&"ui_accept", -2.0)
	_set_status("Connected to %s (%s)!  Security code %s" % [Net.opponent_name(), Net.peer.connection_path(), Net.security_code()], GOLD)
	Net.local_pick = -1
	Net.remote_pick = -1
	GameState.mode = GameState.Mode.ONLINE
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if Net.is_active():
			get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE))


func _on_peer_failed(reason: String) -> void:
	_set_status(reason, BAD)
	if Net.room_role == "guest":
		Net.leave_room()
	_update_controls()


func _on_spectate_closed(reason: String) -> void:
	_set_status(reason, BAD)
	_update_controls()


# --- Room list -------------------------------------------------------------------

func _show_rooms(rooms: Array) -> void:
	if Net.room_role != "":
		return
	rooms = rooms.filter(func(r: Variant) -> bool: return r is Dictionary and r.has("id"))
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _sort_key(a) < _sort_key(b))
	rooms = rooms.slice(0, LIST_ROWS)
	var ids := rooms.map(func(r: Dictionary) -> String: return str(r.id))
	for id: String in _rows.keys():
		if id not in ids:
			var gone: Control = _rows[id]
			_rows.erase(id)
			var refocus := gone.find_children("*", "Button", true, false).any(func(b: Button) -> bool: return b.has_focus())
			gone.queue_free()
			if refocus:
				_create_button.grab_focus()
	_list_empty.visible = rooms.is_empty()
	_list_empty.text = "No rooms yet. Open one, and friends can join with its code."
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var row: HBoxContainer = _rows.get(str(r.id))
		if row == null:
			row = _room_row(str(r.id))
			_list.add_child(row)
			_rows[str(r.id)] = row
		_fill_row(row, r)
		_list.move_child(row, i)


func _show_online(online: Variant) -> void:
	_online.text = online_text(online)
	_online.visible = _online.text != ""


## The server's aggregate `online` object as one line: "23 online · 6 in matches · 3 watching".
## Zero parts are left out; anything missing or malformed (an older server) gives "".
static func online_text(online: Variant) -> String:
	if not (online is Dictionary) or not online.has("players"):
		return ""
	var count := func(key: String) -> int:
		var v: Variant = online.get(key, 0)
		return clampi(int(v), 0, 9_999_999) if (v is int or v is float) else 0
	var players: int = count.call("players")
	if players <= 0:
		return ""
	var parts := ["%d online" % players]
	var in_match: int = count.call("in_match")
	if in_match > 0:
		parts.append("%d in matches" % in_match)
	var watching: int = count.call("spectating")
	if watching > 0:
		parts.append("%d watching" % watching)
	return "  ·  ".join(parts)


## Open rooms first, then matches to watch, then the rest; newest first within each.
func _sort_key(r: Dictionary) -> String:
	var rank := 0 if r.get("status") == "open" and r.get("compatible", false) else 1 if r.get("status") == "in_match" else 2
	return "%d%020d" % [rank, 99999999999999999 - int(r.get("created_at", 0))]


func _room_row(id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := _label("", 22, Color.WHITE)
	label.name = "Text"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var join := _button("Join", 22)
	join.name = "Join"
	join.custom_minimum_size = Vector2(110, 44)
	join.pressed.connect(func() -> void: _join(id))
	row.add_child(join)
	var watch := _button("Watch", 22)
	watch.name = "Watch"
	watch.custom_minimum_size = Vector2(120, 44)
	watch.pressed.connect(func() -> void: _watch(id))
	row.add_child(watch)
	return row


func _fill_row(row: HBoxContainer, r: Dictionary) -> void:
	var compatible: bool = r.get("compatible", false)
	var detail := ""
	match str(r.get("status", "")):
		"open":
			detail = "Waiting for an opponent"
		"full":
			detail = "Getting ready"
		"in_match":
			detail = _match_text(r)
	if not compatible:
		detail = "Version %s: can't join" % r.get("game_version", "?")
	var extras := PackedStringArray()
	if r.get("has_password", false):
		extras.append("password")
	if int(r.get("spectators", 0)) > 0:
		extras.append("%d watching" % int(r.spectators))
	var text := "%s  ·  %s" % [NetPeer.clean_name(str(r.get("name", "Room"))), detail]
	if not extras.is_empty():
		text += "  ·  " + ", ".join(extras)
	(row.get_node("Text") as Label).text = text
	(row.get_node("Join") as Button).disabled = not compatible or r.get("status") != "open"
	(row.get_node("Watch") as Button).disabled = not compatible or not r.get("allow_spectators", false)


func _match_text(r: Dictionary) -> String:
	var names := []
	for slot: Variant in r.get("players", []):
		if slot is Dictionary:
			var fighter := str(slot.get("fighter", ""))
			names.append(fighter.capitalize() if fighter != "" else NetPeer.clean_name(str(slot.get("name", "?"))))
	var text := " vs ".join(names) if names.size() == 2 else "In a match"
	if r.has("round"):
		var wins: Array = r.get("wins", [0, 0])
		text += "  ·  round %d (%d-%d)" % [int(r.round), int(wins[0]), int(wins[1])] if wins.size() == 2 else "  ·  round %d" % int(r.round)
	return text


func _clear_rows() -> void:
	for id: String in _rows:
		(_rows[id] as Control).queue_free()
	_rows.clear()
	_list_empty.visible = true
	_list_empty.text = "Connect to a server to see its rooms." if not Net.is_server_open() else "..."


# --- Layout ----------------------------------------------------------------------

func _update_controls() -> void:
	var open := Net.is_server_open()
	var free := open and Net.room_role == ""
	_connect_button.text = "Disconnect" if open or _connecting else "Connect"
	_url_edit.editable = not open and not _connecting
	_name_edit.editable = not open and not _connecting
	_relay_check.disabled = open or _connecting
	_create_button.disabled = not free
	_join_code_button.disabled = not free
	_watch_code_button.disabled = not free
	for row: HBoxContainer in _rows.values():
		row.visible = free
	match Net.room_role:
		"pending":
			_back_button.text = "Cancel"
		"host":
			_back_button.text = "Close Room"
		"guest", "spectator":
			_back_button.text = "Leave Room"
		_:
			_back_button.text = "Back"
	if not free:
		_list_empty.visible = true
		match Net.room_role:
			"host":
				_list_empty.text = "YOUR ROOM   ·   CODE  %s\n\nGive the code to a friend, or wait for someone from the list." % Net.room_code
			"pending", "guest":
				_list_empty.text = "Joining a room..."
			"spectator":
				_list_empty.text = "Watching a match..."
			_:
				_list_empty.text = "Connect to a server to see its rooms."


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.045, 0.07)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var art := TextureRect.new()
	art.texture = load(WALLPAPER)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.modulate = Color(0.35, 0.35, 0.4)
	add_child(art)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(900, 0)
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	column.add_child(_label("INTERNET LOBBY", 60, GOLD))

	var name_row := _row(column)
	name_row.add_child(_label("Your name", 24, Color.WHITE, 170))
	_name_edit = _line_edit(Settings.online_name(), "Player")
	_name_edit.max_length = 24
	name_row.add_child(_name_edit)

	var url_row := _row(column)
	url_row.add_child(_label("Server", 24, Color.WHITE, 170))
	_url_edit = _line_edit(Settings.server_url if Settings.server_url != "" else DEFAULT_SERVER, "wss://lobby.example.com/v1/ws")
	_url_edit.text_submitted.connect(func(_t: String) -> void: _toggle_connection())
	url_row.add_child(_url_edit)
	_connect_button = _button("Connect", 24)
	_connect_button.custom_minimum_size = Vector2(180, 50)
	_connect_button.pressed.connect(_toggle_connection)
	url_row.add_child(_connect_button)

	_relay_check = CheckBox.new()
	_relay_check.text = "Hide my IP address from opponents (always play through the server's relay)"
	_relay_check.button_pressed = Settings.relay_only
	_relay_check.add_theme_font_size_override("font_size", 20)
	column.add_child(_relay_check)

	var heading := HBoxContainer.new()
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation", 24)
	column.add_child(heading)
	heading.add_child(_label("ROOMS", 22, GOLD))
	_online = _label("", 20, DIM)
	_online.visible = false
	heading.add_child(_online)
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(900, LIST_ROWS * 48 + 16)
	column.add_child(box)
	var inner := VBoxContainer.new()
	box.add_child(inner)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	inner.add_child(_list)
	_list_empty = _label("Connect to a server to see its rooms.", 22, DIM)
	_list_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_empty.custom_minimum_size = Vector2(880, 0)
	inner.add_child(_list_empty)

	var create_row := _row(column)
	_create_button = _button("Open a Room", 24)
	_create_button.custom_minimum_size = Vector2(230, 50)
	_create_button.pressed.connect(_create_room)
	create_row.add_child(_create_button)
	_listed_check = _check("Listed", true)
	create_row.add_child(_listed_check)
	_spectators_check = _check("Spectators", true)
	create_row.add_child(_spectators_check)
	_password_edit = _line_edit("", "Password (optional)")
	_password_edit.secret = true
	_password_edit.max_length = 32
	create_row.add_child(_password_edit)

	var code_row := _row(column)
	code_row.add_child(_label("Room code", 24, Color.WHITE, 170))
	_code_edit = _line_edit("", "e.g. KX7Q2M")
	_code_edit.max_length = 6
	_code_edit.text_submitted.connect(func(t: String) -> void: _join(t))
	code_row.add_child(_code_edit)
	_join_code_button = _button("Join", 24)
	_join_code_button.custom_minimum_size = Vector2(130, 50)
	_join_code_button.pressed.connect(func() -> void: _join(_code_edit.text))
	code_row.add_child(_join_code_button)
	_watch_code_button = _button("Watch", 24)
	_watch_code_button.custom_minimum_size = Vector2(130, 50)
	_watch_code_button.pressed.connect(func() -> void: _watch(_code_edit.text))
	code_row.add_child(_watch_code_button)

	_back_button = _button("Back", 26)
	_back_button.pressed.connect(_back)
	column.add_child(_back_button)

	_status = _label("", 22, DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(900, 84)
	column.add_child(_status)

	_join_prompt = HBoxContainer.new()
	_join_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_prompt.add_theme_constant_override("separation", 20)
	_join_prompt.visible = false
	column.add_child(_join_prompt)
	_accept_button = _button("Accept", 26)
	_accept_button.custom_minimum_size.x = 240
	_accept_button.pressed.connect(_answer.bind(true))
	_join_prompt.add_child(_accept_button)
	var decline := _button("Decline", 26)
	decline.custom_minimum_size.x = 240
	decline.pressed.connect(_answer.bind(false))
	_join_prompt.add_child(decline)


## Asks the game's repository for the official server address (it can move).
func _fetch_server_list() -> void:
	_list_request = HTTPRequest.new()
	_list_request.timeout = 6.0
	add_child(_list_request)
	_list_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var url := official_server(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else ""
		if url == "":
			return
		var following := _url_edit.text.strip_edges() == _official
		_official = url
		if following and not Net.is_server_open() and not _connecting:
			_url_edit.text = url)
	_list_request.request(SERVER_LIST_URL)


## The first usable server address in a servers.json ({"servers": [{"name", "url"}]}),
## or "" if there's none.
static func official_server(json_text: String) -> String:
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary or not parsed.get("servers") is Array:
		return ""
	for entry: Variant in parsed.servers:
		if entry is Dictionary:
			var url := str(entry.get("url", "")).strip_edges()
			if (url.begins_with("wss://") or url.begins_with("ws://")) and url.length() <= 200 and not url.contains(" "):
				return url
	return ""


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	return row


func _button(text: String, size := 28) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 54)
	button.add_theme_font_size_override("font_size", size)
	return button


func _check(text: String, on: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = on
	check.add_theme_font_size_override("font_size", 22)
	return check


func _line_edit(text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 50)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 24)
	return edit


func _label(text: String, size: int, color: Color, width: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if width == 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if width > 0.0:
		label.custom_minimum_size.x = width
	return label
