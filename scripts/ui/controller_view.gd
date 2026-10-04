class_name ControllerView
extends Control
## A drawn gamepad (Xbox layout) for the Controls screen. Each bound button gets a
## callout with its action name; the movement callout points at the D-pad and left
## stick. `highlight` (a button code) glows gold for the selected action, and buttons
## light up live while held on the player's pad.

const BODY := Color(0.16, 0.17, 0.21)
const BODY_EDGE := Color(0.32, 0.34, 0.4)
const DETAIL := Color(0.09, 0.09, 0.12)
const GOLD := Color(1.0, 0.82, 0.3)
const FACE_COLORS := {JOY_BUTTON_A: Color(0.35, 0.75, 0.3), JOY_BUTTON_B: Color(0.85, 0.28, 0.25),
	JOY_BUTTON_X: Color(0.25, 0.5, 0.9), JOY_BUTTON_Y: Color(0.92, 0.75, 0.2)}
const SIZE := Vector2(980, 560)
## Button centers in the SIZE box. The pad body spans x 230..750.
const POS := {
	JOY_BUTTON_Y: Vector2(632, 200), JOY_BUTTON_X: Vector2(588, 244), JOY_BUTTON_B: Vector2(676, 244),
	JOY_BUTTON_A: Vector2(632, 288),
	JOY_BUTTON_LEFT_SHOULDER: Vector2(330, 118), JOY_BUTTON_RIGHT_SHOULDER: Vector2(650, 118),
	InputSetup.PAD_TRIGGER_LEFT: Vector2(330, 72), InputSetup.PAD_TRIGGER_RIGHT: Vector2(650, 72),
	JOY_BUTTON_LEFT_STICK: Vector2(348, 244), JOY_BUTTON_RIGHT_STICK: Vector2(560, 340),
}
const DPAD := Vector2(420, 340)
const BACK_START := [Vector2(445, 210), Vector2(535, 210)]

## "p1" or "p2": whose bindings are shown and whose pad lights up.
var player := "p1"
## Button code to emphasise (the action selected in the list), or -1.
var highlight := -1
var _held := {}


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var device := InputSetup.pad_device(player)
	var held := {}
	for code: int in POS:
		if code >= 100:
			if Input.get_joy_axis(device, code - 100) > 0.5:
				held[code] = true
		elif Input.is_joy_button_pressed(device, code):
			held[code] = true
	for dir in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		if Input.is_joy_button_pressed(device, dir):
			held[dir] = true
	if held != _held:
		_held = held
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	_draw_body()
	_draw_callouts(font) # under the buttons, so lines start at their edges
	# Triggers and bumpers.
	for code in [InputSetup.PAD_TRIGGER_LEFT, InputSetup.PAD_TRIGGER_RIGHT]:
		_round_rect(Rect2(POS[code] - Vector2(52, 20), Vector2(104, 40)), 14, _fill(code, DETAIL))
		_label(font, InputSetup.pad_name(code), POS[code], 18)
	for code in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_round_rect(Rect2(POS[code] - Vector2(70, 16), Vector2(140, 32)), 12, _fill(code, DETAIL))
		_label(font, InputSetup.pad_name(code), POS[code], 18)
	# Sticks, D-pad, Back/Start.
	for code in [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]:
		draw_circle(POS[code], 44, DETAIL)
		draw_circle(POS[code], 30, _fill(code, Color(0.22, 0.23, 0.28)))
	var dpad_color := Color(0.22, 0.23, 0.28)
	for dir in [[Vector2(0, -1), JOY_BUTTON_DPAD_UP], [Vector2(0, 1), JOY_BUTTON_DPAD_DOWN],
			[Vector2(-1, 0), JOY_BUTTON_DPAD_LEFT], [Vector2(1, 0), JOY_BUTTON_DPAD_RIGHT]]:
		var center: Vector2 = DPAD + dir[0] * 24
		draw_rect(Rect2(center - Vector2(16, 16), Vector2(32, 32)), GOLD if _held.has(dir[1]) else dpad_color)
	draw_rect(Rect2(DPAD - Vector2(16, 16), Vector2(32, 32)), dpad_color)
	for p: Vector2 in BACK_START:
		_round_rect(Rect2(p - Vector2(16, 9), Vector2(32, 18)), 9, DETAIL)
	draw_circle(Vector2(490, 150), 22, Color(0.26, 0.27, 0.33)) # home button
	# Face buttons.
	for code: int in FACE_COLORS:
		var color: Color = FACE_COLORS[code]
		draw_circle(POS[code], 24, GOLD if _held.has(code) else color.darkened(0.15))
		if code == highlight:
			draw_arc(POS[code], 29, 0, TAU, 32, GOLD, 4.0, true)
		_label(font, InputSetup.pad_name(code), POS[code], 20)
	if highlight in [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]:
		draw_arc(POS[highlight], 48, 0, TAU, 40, GOLD, 4.0, true)


## Two grips and a body, with an outline.
func _draw_body() -> void:
	var shapes := [[Vector2(330, 330), 120.0], [Vector2(650, 330), 120.0]]
	for edge in [true, false]:
		var grow := 4.0 if edge else 0.0
		var color := BODY_EDGE if edge else BODY
		for s in shapes:
			draw_circle(s[0], s[1] + grow, color)
		_round_rect(Rect2(Vector2(250 - grow, 130 - grow), Vector2(480 + grow * 2, 230 + grow * 2)), 80, color)
		_round_rect(Rect2(Vector2(270 - grow, 92 - grow), Vector2(440 + grow * 2, 70 + grow * 2)), 30, color)


## Callout routes: [exit points from the button..., label lane y, label on the right?].
## Each button has its own lane so lines never cross another button.
const ROUTES := {
	InputSetup.PAD_TRIGGER_RIGHT: [[Vector2(702, 72)], 72.0, true],
	JOY_BUTTON_RIGHT_SHOULDER: [[Vector2(720, 118)], 118.0, true],
	JOY_BUTTON_X: [[Vector2(588, 220), Vector2(588, 160)], 160.0, true],
	JOY_BUTTON_Y: [[Vector2(656, 200)], 200.0, true],
	JOY_BUTTON_B: [[Vector2(700, 244)], 244.0, true],
	JOY_BUTTON_A: [[Vector2(656, 288)], 288.0, true],
	JOY_BUTTON_RIGHT_STICK: [[Vector2(604, 340)], 340.0, true],
	InputSetup.PAD_TRIGGER_LEFT: [[Vector2(278, 72)], 72.0, false],
	JOY_BUTTON_LEFT_SHOULDER: [[Vector2(260, 118)], 118.0, false],
	JOY_BUTTON_LEFT_STICK: [[Vector2(304, 244)], 244.0, false],
}
const LABEL_X := 175.0 # distance of the label column from each edge
const TEXT_COLOR := Color(0.85, 0.87, 0.95)


## Callouts: action names beside the buttons they're bound to, each on its own lane.
func _draw_callouts(font: Font) -> void:
	var labels := {} # button code -> [action names]
	for action: String in InputSetup.PAD_ACTIONS:
		var code: int = InputSetup.bindings[player][action].pad
		if not labels.has(code):
			labels[code] = []
		(labels[code] as Array).append(InputSetup.ACTION_NAMES[action])
	for code: int in labels:
		var route: Array = ROUTES[code]
		var right: bool = route[2]
		var lane: float = route[1]
		var color := GOLD if code == highlight else TEXT_COLOR
		var points := PackedVector2Array([POS[code]])
		for via: Vector2 in route[0]:
			points.append(via)
		var end := Vector2(SIZE.x - LABEL_X if right else LABEL_X, lane)
		points.append(end)
		draw_polyline(points, Color(color, 0.6), 2.0, true)
		draw_circle(end, 4, color)
		_callout_text(font, " / ".join(labels[code]), end, right, color)
	# Movement: D-pad and left stick share one callout, low on the left.
	var move_end := Vector2(LABEL_X, 420)
	for from: Vector2 in [DPAD + Vector2(-30, 14), POS[JOY_BUTTON_LEFT_STICK] + Vector2(-26, 34)]:
		draw_line(from, move_end, Color(TEXT_COLOR, 0.6), 2.0, true)
	draw_circle(move_end, 4, TEXT_COLOR)
	_callout_text(font, "Move / Jump / Crouch", move_end, false, TEXT_COLOR)
	var hint := "Start: pause   ·   Back: training menu"
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2((SIZE.x - hw) / 2.0, SIZE.y - 14), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.57, 0.63))


func _callout_text(font: Font, text: String, end: Vector2, right: bool, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var pos := Vector2(end.x + 12 if right else end.x - 12 - width, end.y + 8)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)


func _fill(code: int, base: Color) -> Color:
	if _held.has(code):
		return GOLD
	if code == highlight:
		return base.lerp(GOLD, 0.45)
	return base


func _round_rect(rect: Rect2, radius: float, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(radius))
	box.anti_aliasing = true
	draw_style_box(box, rect)


func _label(font: Font, text: String, center: Vector2, size: int) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, center + Vector2(-w / 2.0, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
