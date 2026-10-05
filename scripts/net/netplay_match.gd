class_name NetplayMatch
extends Node
## Runs an online fight: takes over the FightManager's tick with a RollbackSession fed by
## this machine's Player 1 controls and the Net connection, and shows the connection
## (ping, rollback, quality bars). Esc asks before leaving (an online match can't pause).
## Handles the opponent leaving, the connection dropping, and desyncs.
## In an internet room it also publishes the match to spectators (SpectatorFeed.Publisher:
## setup, confirmed inputs, checksums, result) and keeps the room's listing up to date.

const QUALITY_COLORS := [Color(0.9, 0.25, 0.2), Color(0.95, 0.55, 0.2), Color(0.95, 0.8, 0.25), Color(0.6, 0.85, 0.3), Color(0.3, 0.85, 0.4)]
const STALL_NOTICE_TICKS := 30 # waiting this long for the opponent shows a notice
const SMOKE_CHECK_TICK := 1200
const ROOM_REPORT_TICKS := 30 # how often the room's round / wins are checked

var manager: Node # FightManager
var session: RollbackSession
var controls := PlayerController.new("p1_")
var ended := false

var _status: Label
var _leave_prompt: PanelContainer
var _stalled_for := 0
var _rng := RandomNumberGenerator.new() # smoke test inputs only
var _smoke_input := InputBuffer.pack(InputBuffer.NEUTRAL, 0)
var _smoke_hold := 0
var _smoke_done := false
var _publisher: SpectatorFeed.Publisher
var _reported := [] # round and wins last sent to the server


func setup(fight_manager: Node) -> void:
	manager = fight_manager
	name = "NetplayMatch"
	manager.set_physics_process(false)
	session = RollbackSession.new(manager, Net.local_index, Net.input_delay, GameState.match_seed)
	session.desynced.connect(_on_desynced)
	Net.peer.input_received.connect(session.receive_packet)
	Net.left.connect(_on_left)
	Net.rematch_changed.connect(_on_rematch_changed)
	_rng.seed = GameState.match_seed + Net.local_index
	_build_ui()
	var hud: FightHud = manager.hud
	var local_name := Settings.online_name()
	var names := [local_name, Net.opponent_name()] if Net.is_host() else [Net.opponent_name(), local_name]
	hud.p1_name.text = "%s  ·  %s" % [manager.fighters[0].data.display_name, names[0]]
	hud.p2_name.text = "%s  ·  %s" % [names[1], manager.fighters[1].data.display_name]
	hud.configure_result("Rematch", "Character Select", "Leave")
	if Net.publishing():
		_start_publishing(names)


func _exit_tree() -> void:
	if Net.peer and Net.peer.input_received.is_connected(session.receive_packet):
		Net.peer.input_received.disconnect(session.receive_packet)
	if Net.left.is_connected(_on_left):
		Net.left.disconnect(_on_left)
		Net.rematch_changed.disconnect(_on_rematch_changed)


func _physics_process(_delta: float) -> void:
	if ended:
		return
	if not Net.is_active():
		_on_left(Net.last_reason if Net.last_reason != "" else "Connection lost")
		return
	session.rtt_ticks = Net.rtt_ms() * 60.0 / 1000.0
	var input := _local_input()
	var advanced := session.advance(input)
	Net.peer.send_input(session.make_packet())
	if _publisher:
		_publish()
	_stalled_for = 0 if advanced else _stalled_for + 1
	if Engine.get_physics_frames() % 10 == 0 or not advanced:
		_update_status()
	if Net.smoke:
		_smoke_check()


func _local_input() -> int:
	if Net.smoke:
		return _smoke_next()
	if _leave_prompt.visible:
		return InputBuffer.pack(InputBuffer.NEUTRAL, 0)
	return controls.read_raw()


## Esc: show or hide the leave prompt (FightManager forwards it; the tree never pauses).
func toggle_leave_prompt() -> void:
	if ended:
		return
	_leave_prompt.visible = not _leave_prompt.visible
	if _leave_prompt.visible:
		(_leave_prompt.find_child("Stay", true, false) as Button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _leave_prompt.visible and event.is_action_pressed("ui_cancel"):
		_leave_prompt.visible = false
		get_viewport().set_input_as_handled()


func request_rematch() -> void:
	if Net.is_active():
		Net.request_rematch()


func leave() -> void:
	ended = true
	_finish_feed(SpectatorFeed.Result.ABORTED)
	var exit := Net.exit_scene()
	Net.leave()
	manager._go_to(exit)


# --- Events ----------------------------------------------------------------------

func _on_left(reason: String) -> void:
	if ended:
		return
	ended = true
	_finish_feed(SpectatorFeed.Result.ABORTED)
	_leave_prompt.visible = false
	_status.text = ""
	manager.hud.announce("DISCONNECTED", reason.to_upper(), true)
	manager.hud.configure_result("", "", "Main Menu")
	manager.hud.show_result()
	if Net.smoke:
		print("SMOKE TEST: online opponent left (%s)" % reason)


func _on_desynced(frame: int, local_checksum: int, remote_checksum: int) -> void:
	push_error("Netplay desync at tick %d (local %08x, remote %08x)" % [frame, local_checksum, remote_checksum])
	ended = true
	_finish_feed(SpectatorFeed.Result.ABORTED)
	manager.hud.announce("DESYNC", "THE MATCH WAS STOPPED", true)
	manager.hud.configure_result("", "", "Leave")
	manager.hud.show_result()
	if Net.smoke:
		print("SMOKE TEST: online DESYNC at tick %d" % frame)
		get_tree().quit(1)


func _on_rematch_changed() -> void:
	if Net.rematch_local and not Net.rematch_remote:
		manager.hud.configure_result("Waiting for opponent...", "Character Select", "Leave")
	elif Net.rematch_remote and not Net.rematch_local:
		manager.hud.configure_result("Rematch (opponent is ready)", "Character Select", "Leave")


# --- Spectator feed (internet rooms) -----------------------------------------------

func _start_publishing(names: Array) -> void:
	_publisher = SpectatorFeed.Publisher.new(session, Net.publish)
	var p1: CharacterData = manager.fighters[0].data
	var p2: CharacterData = manager.fighters[1].data
	var stage_id := GameState.stage_path.get_file().get_basename()
	_publisher.start(maxi(GameState.stage_paths().find(GameState.stage_path), 0), GameState.roster.find(p1), GameState.roster.find(p2),
		PackedStringArray([GameState.game_version(), stage_id, p1.id, p2.id, names[0], names[1]]))
	_reported = [1, [0, 0]]
	Net.report_room("in_match", {fighters = [str(p1.id), str(p2.id)], stage = stage_id, round = 1, wins = [0, 0]})


## Confirmed inputs to the server; the result once the match is over and confirmed (no
## prediction left, so a rollback can't change it any more); the round now and then.
func _publish() -> void:
	_publisher.update(Time.get_ticks_msec())
	if session.prediction_depth() > 0:
		return
	if manager.phase == manager.Phase.MATCH_OVER and not _publisher.ended:
		var wins: Array = manager.round_wins
		var result := SpectatorFeed.Result.DRAW
		if manager.match_winner:
			result = SpectatorFeed.Result.P1_WON if manager.match_winner == manager.fighters[0] else SpectatorFeed.Result.P2_WON
		_publisher.finish(result, wins[0], wins[1], Time.get_ticks_msec())
		Net.report_room("results", {round = manager.round_number, wins = [wins[0], wins[1]]})
	elif session.frame % ROOM_REPORT_TICKS == 0 and manager.phase != manager.Phase.MATCH_OVER:
		var now := [manager.round_number, [manager.round_wins[0], manager.round_wins[1]]]
		if now != _reported:
			_reported = now
			Net.report_room("in_match", {round = now[0], wins = now[1]})


func _finish_feed(result: int) -> void:
	if _publisher and not _publisher.ended:
		_publisher.finish(result, manager.round_wins[0], manager.round_wins[1], Time.get_ticks_msec())


# --- Connection display ----------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.offset_bottom = -14
	layer.add_child(_status)

	_leave_prompt = PanelContainer.new()
	_leave_prompt.visible = false
	_leave_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_leave_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_leave_prompt.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	style.border_color = Color(1.0, 0.82, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	_leave_prompt.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_leave_prompt.add_child(box)
	var question := Label.new()
	question.text = "Leave the match?\nThe game keeps running: an online match can't pause.\nSecurity code %s" % Net.security_code()
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.add_theme_font_size_override("font_size", 26)
	box.add_child(question)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var stay := Button.new()
	stay.name = "Stay"
	stay.text = "Keep Playing"
	stay.custom_minimum_size = Vector2(220, 54)
	stay.add_theme_font_size_override("font_size", 26)
	stay.pressed.connect(func() -> void: _leave_prompt.visible = false)
	row.add_child(stay)
	var quit := Button.new()
	quit.text = "Leave"
	quit.custom_minimum_size = Vector2(220, 54)
	quit.add_theme_font_size_override("font_size", 26)
	quit.pressed.connect(leave)
	row.add_child(quit)
	layer.add_child(_leave_prompt)


func _update_status() -> void:
	if ended:
		return
	if _stalled_for >= STALL_NOTICE_TICKS:
		_status.text = "Waiting for opponent..."
		_status.modulate = QUALITY_COLORS[1]
		return
	var rtt := Net.rtt_ms()
	var quality := 5 if rtt < 60 else 4 if rtt < 100 else 3 if rtt < 150 else 2 if rtt < 220 else 1
	_status.text = "%s   PING %d ms   ROLLBACK %d   DELAY %d" % [
		"▮".repeat(quality) + "▯".repeat(5 - quality), roundi(rtt), session.prediction_depth(), session.input_delay]
	_status.modulate = QUALITY_COLORS[quality - 1]


# --- Smoke test ------------------------------------------------------------------

func _smoke_next() -> int:
	if _smoke_hold <= 0:
		var toward := 6 if Net.is_host() else 4
		var dir: int = [toward, toward, 5, 2, 3 if toward == 6 else 1, 4 if toward == 6 else 6][_rng.randi() % 6]
		var buttons: int = 0 if _rng.randf() < 0.55 else [InputBuffer.LP, InputBuffer.HP, InputBuffer.LK, InputBuffer.HK][_rng.randi() % 4]
		_smoke_hold = _rng.randi_range(2, 10)
		_smoke_input = InputBuffer.pack(dir, buttons)
		return _smoke_input
	_smoke_hold -= 1
	return _smoke_input & 0xF # buttons only on the first tick


func _smoke_check() -> void:
	if _smoke_done or not session.checksums.has(SMOKE_CHECK_TICK):
		return
	_smoke_done = true
	print("SMOKE TEST: online checksum at tick %d = %08x (rollbacks %d, %d ticks re-run, stalls %d)" % [
		SMOKE_CHECK_TICK, session.checksums[SMOKE_CHECK_TICK], session.rollbacks, session.rollback_ticks, session.stalls])
	# Keep sending for a moment so the opponent can confirm its own checksum too (and, in
	# an internet room, so spectators get past this tick despite the feed's delay).
	get_tree().create_timer(8.0 if _publisher else 1.5).timeout.connect(func() -> void:
		Net.leave()
		get_tree().quit())
