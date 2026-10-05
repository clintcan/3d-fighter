class_name SpectatorMatch
extends Node
## Watches an internet match from the lobby server's spectator feed (Net.feed): takes over
## the FightManager's tick and re-simulates the match from both players' inputs, which
## reproduces it exactly (the simulation is deterministic). Joining late fast-forwards
## through the backlog with effects muted; a small backlog plays slightly fast to catch
## up. The host's checksums are checked as the match plays: a mismatch (different game
## data, or a tampered feed) stops the replay instead of showing a different fight.
## After MATCH_END the match plays on with neutral inputs, so the victory scene shows.
## Keys 1-6 send reactions; Esc asks before leaving.

const CATCH_UP_TICKS := 90 # more buffered than this: fast-forward, muted
const MAX_TICKS_PER_FRAME := 240 # ~60 ms of simulation per frame while catching up
const SPEED_UP_TICKS := 20 # a little behind: two ticks per frame
const WAIT_NOTICE_TICKS := 45
const REACTION_COOLDOWN_MS := 2000
const REACTION_SHOW_MS := 3500
const EMOTE_LABELS := {clap = "CLAP", fire = "FIRE", wow = "WOW", laugh = "HAHA", gg = "GG", ouch = "OUCH"}
const SMOKE_CHECK_TICK := 1200

var manager: Node # FightManager
## The next tick to simulate.
var frame := 0
var ended := false
var diverged := false
## Host checksums this replay matched.
var checks_passed := 0

var _log: SpectatorFeed.Log
var _controllers: Array[NetInputController] = []
var _status: Label
var _reactions: VBoxContainer
var _leave_prompt: PanelContainer
var _waiting := 0
var _last_react := -REACTION_COOLDOWN_MS
var _smoke_done := false


func setup(fight_manager: Node) -> void:
	manager = fight_manager
	name = "SpectatorMatch"
	manager.set_physics_process(false)
	for fighter: Fighter in manager.fighters:
		var controller := NetInputController.new()
		fighter.controller = controller
		_controllers.append(controller)
	_log = Net.feed
	Net.spectate_closed.connect(_on_closed)
	Net.reaction_received.connect(_on_reaction)
	_build_ui()
	var hud: FightHud = manager.hud
	var start := _log.start
	hud.p1_name.text = "%s  ·  %s" % [manager.fighters[0].data.display_name, start.get("p1_name", "P1")]
	hud.p2_name.text = "%s  ·  %s" % [start.get("p2_name", "P2"), manager.fighters[1].data.display_name]
	hud.configure_result("", "", "Leave")


func _exit_tree() -> void:
	if Net.spectate_closed.is_connected(_on_closed):
		Net.spectate_closed.disconnect(_on_closed)
		Net.reaction_received.disconnect(_on_reaction)


func _physics_process(_delta: float) -> void:
	if ended:
		return
	if not _log.end.is_empty() and frame >= int(_log.end.final_tick):
		_step(InputBuffer.pack(InputBuffer.NEUTRAL, 0), InputBuffer.pack(InputBuffer.NEUTRAL, 0)) # decided: play out the victory
		_update_status(0)
		return
	var available := _log.ticks() - frame
	if available <= 0:
		_waiting += 1
		_update_status(0)
		return
	_waiting = 0
	var steps := 1
	if available > CATCH_UP_TICKS:
		steps = mini(available - SPEED_UP_TICKS, MAX_TICKS_PER_FRAME)
	elif available > SPEED_UP_TICKS:
		steps = 2
	var muted := steps > 2
	manager.resimulating = muted
	for i in steps:
		if not _step_feed():
			break
	manager.resimulating = false
	if muted and _log.ticks() - frame <= CATCH_UP_TICKS:
		# Caught up. The muted ticks skipped the call-outs, so clear the one from the
		# start ("ROUND 1"), and no camera swoop from wherever it was.
		if manager.phase == manager.Phase.FIGHT:
			manager.hud.announce("")
		if manager.camera.manager:
			manager.camera.snap()
	_update_status(_log.ticks() - frame)
	if Net.server_smoke != "":
		_smoke_check()


## One tick from the feed, after checking the host's checksum for it. False on divergence.
func _step_feed() -> bool:
	if _log.checksums.has(frame):
		var mine: int = manager.checksum(manager.save_state())
		if mine != int(_log.checksums[frame]):
			_diverge(mine, int(_log.checksums[frame]))
			return false
		checks_passed += 1
	_step(_log.p1[frame], _log.p2[frame])
	return true


func _step(p1: int, p2: int) -> void:
	_controllers[0].raw = p1
	_controllers[1].raw = p2
	manager.step()
	frame += 1


func _diverge(mine: int, theirs: int) -> void:
	push_warning("Spectator replay diverged at tick %d (local %08x, host %08x)" % [frame, mine, theirs])
	diverged = true
	ended = true
	manager.hud.announce("OUT OF SYNC", "THIS REPLAY DOESN'T MATCH THE HOST'S", true)
	manager.hud.show_result()
	_status.text = ""
	if Net.server_smoke != "":
		print("SMOKE TEST: spectator DIVERGED at tick %d" % frame)
		get_tree().quit(1)


func _unhandled_input(event: InputEvent) -> void:
	if _leave_prompt.visible:
		if event.is_action_pressed("ui_cancel"):
			_leave_prompt.visible = false
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var index: int = event.keycode - KEY_1
		if index >= 0 and index < Net.EMOTES.size():
			_send_reaction(Net.EMOTES[index])
			get_viewport().set_input_as_handled()


func _send_reaction(emote: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_react < REACTION_COOLDOWN_MS:
		return
	_last_react = now
	Net.react(emote)


# --- FightManager hooks (the same calls it makes on a NetplayMatch) -----------------

func toggle_leave_prompt() -> void:
	_leave_prompt.visible = not _leave_prompt.visible
	if _leave_prompt.visible:
		(_leave_prompt.find_child("Stay", true, false) as Button).grab_focus()


func request_rematch() -> void:
	pass # spectators don't play


func leave() -> void:
	ended = true
	Net.stop_spectating()
	manager._go_to(Net.exit_scene())


# --- Events ----------------------------------------------------------------------

func _on_closed(reason: String) -> void:
	if ended:
		return
	ended = true
	_leave_prompt.visible = false
	_status.text = ""
	manager.hud.announce("SPECTATING ENDED", reason.to_upper(), true)
	manager.hud.show_result()


func _on_reaction(from_name: String, emote: String) -> void:
	if not EMOTE_LABELS.has(emote):
		return
	var label := Label.new()
	label.text = "%s  %s" % [from_name, EMOTE_LABELS[emote]]
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_constant_override("outline_size", 7)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reactions.add_child(label)
	while _reactions.get_child_count() > 5:
		_reactions.get_child(0).free()
	var tween := label.create_tween()
	tween.tween_interval(REACTION_SHOW_MS / 1000.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


# --- Display ---------------------------------------------------------------------

func _update_status(behind: int) -> void:
	if ended:
		return
	var watchers := int(Net.room.get("spectators", 0))
	var delay := "LIVE (%d s DELAY)" % roundi(Net.spectate_delay_ms / 1000.0) if Net.spectate_delay_ms > 0 else "LIVE"
	if behind > CATCH_UP_TICKS:
		delay = "CATCHING UP  %d s" % ceili(behind / 60.0)
	elif _waiting >= WAIT_NOTICE_TICKS and _log.end.is_empty():
		delay = "WAITING FOR THE MATCH..."
	elif not _log.end.is_empty() and frame >= int(_log.end.final_tick):
		delay = "MATCH OVER"
	_status.text = "SPECTATING   %s   %d WATCHING   [1-6] REACT   [ESC] LEAVE" % [delay, watchers]


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.offset_bottom = -14
	layer.add_child(_status)

	_reactions = VBoxContainer.new()
	_reactions.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_reactions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_reactions.grow_vertical = Control.GROW_DIRECTION_BOTH
	_reactions.offset_right = -24
	_reactions.alignment = BoxContainer.ALIGNMENT_END
	_reactions.add_theme_constant_override("separation", 6)
	_reactions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_reactions)

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
	question.text = "Stop watching?"
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.add_theme_font_size_override("font_size", 26)
	box.add_child(question)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var stay := Button.new()
	stay.name = "Stay"
	stay.text = "Keep Watching"
	stay.custom_minimum_size = Vector2(240, 54)
	stay.add_theme_font_size_override("font_size", 26)
	stay.pressed.connect(func() -> void: _leave_prompt.visible = false)
	row.add_child(stay)
	var quit := Button.new()
	quit.text = "Leave"
	quit.custom_minimum_size = Vector2(240, 54)
	quit.add_theme_font_size_override("font_size", 26)
	quit.pressed.connect(leave)
	row.add_child(quit)
	layer.add_child(_leave_prompt)


func _smoke_check() -> void:
	if _smoke_done or frame <= SMOKE_CHECK_TICK:
		return
	_smoke_done = true
	print("SMOKE TEST: spectator reached tick %d, %d host checksum(s) matched, checksum at %d = %08x" % [
		frame, checks_passed, SMOKE_CHECK_TICK, int(_log.checksums.get(SMOKE_CHECK_TICK, 0))])
