extends Control
## Online menu: host a game, pick one found on the local network (LanBrowser), or join by
## address; then on to character select once connected (Net autoload). Shows why the last
## connection ended, if it did.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const CHARACTER_SELECT_SCENE := "res://scenes/character_select.tscn"
const WALLPAPER := "res://assets/ui/wallpaper.png"
const GOLD := Color(1.0, 0.82, 0.3)
const DIM := Color(0.72, 0.75, 0.82)
const LIST_ROWS := 4
const NOTHING_FOUND_MS := 4000 # searching this long with no result shows the hint

var _name_edit: LineEdit
var _address_edit: LineEdit
var _host_button: Button
var _join_button: Button
var _back_button: Button
var _status: Label
var _busy := false
var _browser: LanBrowser
var _lan_list: VBoxContainer
var _lan_empty: Label
var _browse_started := 0
var _lan_rows := {} # host session id -> Button
var _join_prompt: HBoxContainer
var _accept_button: Button


func _ready() -> void:
	Audio.music(&"menu")
	_build()
	Net.connected.connect(_on_connected)
	Net.connect_failed.connect(_on_failed)
	Net.join_requested.connect(_on_join_requested)
	Net.join_cancelled.connect(_on_join_cancelled)
	Net.join_pending.connect(_on_join_pending)
	if Net.last_reason != "":
		_set_status(Net.last_reason, Color(1.0, 0.55, 0.45))
		Net.last_reason = ""
	NetPeer.prepare_host_key() # in the background, so hosting never waits for it
	_browser = LanBrowser.new(GameState.game_version(), GameState.content_hash())
	_browser.games_changed.connect(_refresh_lan)
	_start_browsing()
	_host_button.grab_focus()


func _exit_tree() -> void:
	Net.connected.disconnect(_on_connected)
	Net.connect_failed.disconnect(_on_failed)
	Net.join_requested.disconnect(_on_join_requested)
	Net.join_cancelled.disconnect(_on_join_cancelled)
	Net.join_pending.disconnect(_on_join_pending)
	_browser.games_changed.disconnect(_refresh_lan) # the list is going away with us
	_browser.stop()


func _process(_delta: float) -> void:
	_browser.poll()
	if _browser.is_running() and _browser.games.is_empty():
		var searching := Time.get_ticks_msec() - _browse_started < NOTHING_FOUND_MS
		_lan_empty.text = "Searching..." if searching else \
			"No games found yet. Ask the host for their address, or check that you're on the same network (guest Wi-Fi and VPNs can hide games)."


func _start_browsing() -> void:
	if _browser.start() != OK:
		_lan_empty.text = "Can't search the network on this machine."
		return
	_browse_started = Time.get_ticks_msec()
	_refresh_lan()


## Updates the list of games found on the network in place (rows are kept per host, so
## focus and clicks aren't lost when a ping changes).
func _refresh_lan() -> void:
	var games := _browser.sorted_games().slice(0, LIST_ROWS)
	var ids := games.map(func(g: Dictionary) -> int: return g.id)
	for id: int in _lan_rows.keys():
		if id not in ids:
			var gone: Button = _lan_rows[id]
			_lan_rows.erase(id)
			var refocus := gone.has_focus()
			gone.queue_free()
			if refocus:
				_host_button.grab_focus()
	_lan_empty.visible = games.is_empty()
	for i in games.size():
		var game: Dictionary = games[i]
		var button: Button = _lan_rows.get(game.id)
		if button == null:
			button = _button("")
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(760, 52)
			button.add_theme_font_size_override("font_size", 26)
			button.pressed.connect(_join_found.bind(game.id))
			_lan_list.add_child(button)
			_lan_rows[game.id] = button
		var detail := "Waiting for an opponent  ·  %d ms" % game.ping_ms
		if not game.compatible:
			detail = "Different version (%s): can't join" % game.version
		elif game.status != 0:
			detail = "In a match"
		button.text = "  %s   —   %s" % [game.name, detail]
		button.disabled = not game.compatible or game.status != 0
		button.tooltip_text = "%s:%d" % [game.ip, game.port]
		_lan_list.move_child(button, i)


func _join_found(id: int) -> void:
	var game: Dictionary = _browser.games.get(id, {})
	if not game.is_empty():
		_join_address("%s:%d" % [game.ip, game.port])


func _host() -> void:
	_save_name()
	_browser.stop() # don't list our own game
	var err := Net.host()
	if err != OK:
		_set_status("Couldn't host on port %d (is another copy of the game hosting?)" % NetPeer.DEFAULT_PORT, Color(1.0, 0.55, 0.45))
		_start_browsing()
		return
	_set_busy(true)
	var addresses := _local_addresses()
	_set_status("Hosting on port %d. Waiting for an opponent...\nYour address: %s\nOver the internet, forward UDP port %d on your router; allow the game through your firewall if asked." % [
		NetPeer.DEFAULT_PORT, ", ".join(addresses) if not addresses.is_empty() else "unknown", NetPeer.DEFAULT_PORT], DIM)


func _join() -> void:
	_join_address(_address_edit.text.strip_edges())


func _join_address(address: String) -> void:
	if address == "":
		_set_status("Type the host's address first (for example 192.168.1.20).", Color(1.0, 0.55, 0.45))
		_address_edit.grab_focus()
		return
	_save_name()
	Settings.last_join_address = address
	Settings.save_settings()
	_address_edit.text = address
	var err := Net.join(address)
	if err != OK:
		_set_status("Can't connect to \"%s\": check the address." % address, Color(1.0, 0.55, 0.45))
		return
	_browser.stop()
	_set_busy(true)
	_set_status("Connecting to %s..." % address, DIM)


func _back() -> void:
	Audio.sfx(&"ui_back", -4.0)
	if _busy:
		Net.leave() # cancel hosting / joining
		_join_prompt.visible = false
		_set_busy(false)
		_set_status("Cancelled.", DIM)
		_start_browsing()
		_host_button.grab_focus()
	else:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Host: someone asks to join. They only get in if the host accepts.
func _on_join_requested(name: String) -> void:
	Audio.sfx(&"ui_accept", -4.0)
	_set_status("%s wants to join your game." % name, GOLD)
	_join_prompt.visible = true
	_accept_button.grab_focus()


func _on_join_cancelled(name: String) -> void:
	_join_prompt.visible = false
	_set_status("%s stopped trying to join. Still waiting for an opponent..." % name, DIM)
	_back_button.grab_focus()


func _answer_join(accept: bool) -> void:
	_join_prompt.visible = false
	if accept:
		Net.accept_join()
	else:
		Net.decline_join()
		_set_status("Declined. Still waiting for an opponent...", DIM)
		_back_button.grab_focus()


## Guest: the host has been asked.
func _on_join_pending(host_name: String) -> void:
	_set_status("Waiting for %s to accept..." % host_name, DIM)


func _on_connected() -> void:
	_join_prompt.visible = false
	Audio.sfx(&"ui_accept", -2.0)
	_set_status("Connected to %s!  Security code %s" % [Net.opponent_name(), Net.security_code()], GOLD)
	Net.local_pick = -1
	Net.remote_pick = -1
	GameState.mode = GameState.Mode.ONLINE
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if Net.is_active():
			get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE))


func _on_failed(reason: String) -> void:
	_set_busy(false)
	_start_browsing()
	_set_status(reason, Color(1.0, 0.55, 0.45))
	_join_button.grab_focus()


func _save_name() -> void:
	Settings.player_name = _name_edit.text.strip_edges().left(24)
	Settings.save_settings()


func _set_busy(busy: bool) -> void:
	_busy = busy
	_host_button.disabled = busy
	_join_button.disabled = busy
	_address_edit.editable = not busy
	_name_edit.editable = not busy
	_back_button.text = "Cancel" if busy else "Back"
	if busy:
		_lan_empty.text = "Not searching while you host or join."
	if busy:
		_back_button.grab_focus()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


## This machine's IPv4 LAN addresses (what the guest types).
func _local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			out.append(address)
	return out


# --- Layout ----------------------------------------------------------------------

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
	column.custom_minimum_size = Vector2(760, 0)
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	column.add_child(_label("ONLINE", 72, GOLD))
	column.add_child(_label("Play a friend over your network or the internet.", 24, DIM))

	var name_row := _row(column)
	name_row.add_child(_label("Your name", 26, Color.WHITE, 220))
	_name_edit = _line_edit(Settings.online_name(), "Player")
	_name_edit.max_length = 24
	name_row.add_child(_name_edit)

	_host_button = _button("Host Game")
	_host_button.pressed.connect(_host)
	column.add_child(_host_button)

	column.add_child(_label("GAMES ON YOUR NETWORK", 22, GOLD))
	var lan_box := PanelContainer.new()
	var lan_style := StyleBoxFlat.new()
	lan_style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	lan_style.set_corner_radius_all(8)
	lan_style.set_content_margin_all(8)
	lan_box.add_theme_stylebox_override("panel", lan_style)
	lan_box.custom_minimum_size = Vector2(760, LIST_ROWS * 56 + 16)
	column.add_child(lan_box)
	var lan_inner := VBoxContainer.new()
	lan_box.add_child(lan_inner)
	_lan_list = VBoxContainer.new()
	_lan_list.add_theme_constant_override("separation", 4)
	lan_inner.add_child(_lan_list)
	_lan_empty = _label("Searching...", 22, DIM)
	_lan_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lan_empty.custom_minimum_size = Vector2(740, 0)
	lan_inner.add_child(_lan_empty)
	column.add_child(_label("OR JOIN BY ADDRESS", 22, GOLD))

	var join_row := _row(column)
	_address_edit = _line_edit(Settings.last_join_address, "Host address, e.g. 192.168.1.20")
	_address_edit.text_submitted.connect(func(_t: String) -> void: _join())
	join_row.add_child(_address_edit)
	_join_button = _button("Join")
	_join_button.custom_minimum_size.x = 180
	_join_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_join_button.pressed.connect(_join)
	join_row.add_child(_join_button)

	_back_button = _button("Back")
	_back_button.pressed.connect(_back)
	column.add_child(_back_button)

	_status = _label("", 22, DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(760, 110)
	column.add_child(_status)

	_join_prompt = HBoxContainer.new()
	_join_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_prompt.add_theme_constant_override("separation", 20)
	_join_prompt.visible = false
	column.add_child(_join_prompt)
	_accept_button = _button("Accept")
	_accept_button.custom_minimum_size.x = 240
	_accept_button.pressed.connect(_answer_join.bind(true))
	_join_prompt.add_child(_accept_button)
	var decline := _button("Decline")
	decline.custom_minimum_size.x = 240
	decline.pressed.connect(_answer_join.bind(false))
	_join_prompt.add_child(decline)


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	return row


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 60)
	button.add_theme_font_size_override("font_size", 30)
	return button


func _line_edit(text: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 56)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 26)
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
