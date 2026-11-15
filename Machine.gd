extends Node2D
## Interactable machine: the ship computer (shop), the oxygen concentrator
## and the fuel tank. Drawn procedurally so it matches the grow beds.
##
## Machines are walk-up props with no collision body: the room's lanes are only
## a little wider than the player, so a solid footprint here would wedge the
## player against a wall or seal the passage next to the beds.

var kind: String = "computer"
var label: Label
var _w := 90.0
var _h := 90.0
var _bar_ratio := 0.0
var _bar_color := Color(0.3, 0.8, 1.0)
var _glow := 0.0

func setup(machine_kind: String) -> void:
	kind = machine_kind
	match kind:
		"computer":
			_w = 130.0
			_h = 0.0
		"oxygen":
			_w = 96.0
			_h = 104.0
		"fuel":
			_w = 76.0
			_h = 96.0

	label = Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.position = Vector2(-_w * 0.5 - 8, -_h - 24)
	label.size = Vector2(_w + 16, 20)
	add_child(label)

	refresh()
	set_process(kind != "computer")

func prompt() -> String:
	match kind:
		"computer":
			return "[E] Use the ship computer"
		"oxygen":
			return "[E] Oxygen concentrator (%s)" % ("ON" if Global.oxygen_machine_on else "OFF")
		"fuel":
			return "[E] Fuel tank"
	return ""

func refresh() -> void:
	match kind:
		"computer":
			label.text = "SHIP COMPUTER"
		"oxygen":
			var on := Global.oxygen_machine_on
			label.text = "O2 MAKER: %s" % ("ON" if on else "OFF")
			_bar_ratio = Global.oxygen / Global.MAX_OXYGEN
			_bar_color = Color(0.3, 0.8, 1.0) if on else Color(0.4, 0.4, 0.4)
		"fuel":
			label.text = "FUEL %d / %d" % [roundi(Global.fuel), int(Global.MAX_FUEL)]
			_bar_ratio = Global.fuel / Global.MAX_FUEL
			_bar_color = Color(1.0, 0.6, 0.2)
	queue_redraw()

func _process(delta: float) -> void:
	_glow = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 400.0)
	queue_redraw()

func _draw() -> void:
	match kind:
		"oxygen":
			_draw_oxygen()
		"fuel":
			_draw_fuel()

func _panel(rect: Rect2, fill: Color) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, Color(0.09, 0.11, 0.14, 1.0), false, 2.0)

func _draw_oxygen() -> void:
	draw_rect(Rect2(-_w * 0.5 - 4, -4, _w + 8, 8), Color(0, 0, 0, 0.35), true)
	_panel(Rect2(-48, -104, 96, 104), Color(0.27, 0.32, 0.37, 1.0))
	_panel(Rect2(-42, -112, 84, 9), Color(0.42, 0.48, 0.55, 1.0))

	# Screen.
	_panel(Rect2(-38, -98, 54, 42), Color(0.07, 0.09, 0.12, 1.0))
	var on := Global.oxygen_machine_on
	var scr := Color(0.15, 0.60, 0.70) if on else Color(0.18, 0.20, 0.22)
	draw_rect(Rect2(-34, -94, 46, 34), scr, true)
	if on:
		draw_rect(Rect2(-34, -94 + 34.0 * (1.0 - clampf(_bar_ratio, 0.0, 1.0)), 46,
			34.0 * clampf(_bar_ratio, 0.0, 1.0)), scr.lightened(0.25), true)
		draw_rect(Rect2(-34, -94, 46, 2), Color(0.6, 0.95, 1.0, 0.5), true)

	# Vent grille.
	for i in 4:
		draw_rect(Rect2(14, -92 + i * 9, 26, 4), Color(0.16, 0.19, 0.23, 1.0), true)

	# Status LED.
	var led := Color(0.35, 1.0, 0.45) if on else Color(1.0, 0.35, 0.3)
	draw_circle(Vector2(-36, -40), 4.0, led)
	if on:
		draw_circle(Vector2(-36, -40), 7.0, Color(led.r, led.g, led.b, 0.18 + 0.12 * _glow))

	# O2 level strip.
	var bar := Rect2(-38, -46, 40, 6)
	draw_rect(bar, Color(0.05, 0.08, 0.12, 0.95), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_bar_ratio, 0.0, 1.0), bar.size.y)),
		_bar_color, true)

func _draw_fuel() -> void:
	draw_rect(Rect2(-_w * 0.5 - 4, -4, _w + 8, 8), Color(0, 0, 0, 0.35), true)
	# Tank body.
	_panel(Rect2(-34, -86, 68, 86), Color(0.31, 0.34, 0.40, 1.0))
	# Top cap and neck.
	draw_rect(Rect2(-22, -97, 44, 12), Color(0.45, 0.48, 0.54, 1.0), true)
	draw_rect(Rect2(-22, -97, 44, 12), Color(0.09, 0.11, 0.14, 1.0), false, 2.0)
	draw_rect(Rect2(-7, -104, 14, 8), Color(0.55, 0.58, 0.62, 1.0), true)

	# Level window.
	var win := Rect2(-18, -74, 36, 40)
	draw_rect(win, Color(0.06, 0.08, 0.11, 1.0), true)
	var level := clampf(_bar_ratio, 0.0, 1.0)
	if level > 0.0:
		var h := win.size.y * level
		draw_rect(Rect2(win.position.x + 2, win.position.y + win.size.y - h + 2,
			win.size.x - 4, maxf(h - 4, 1.0)), Color(1.0, 0.62, 0.2, 0.95), true)
	draw_rect(win, Color(0.09, 0.11, 0.14, 1.0), false, 2.0)

	# Bands and hazard stripe.
	draw_rect(Rect2(-34, -26, 68, 4), Color(0.18, 0.20, 0.25, 1.0), true)
	draw_rect(Rect2(-34, -14, 68, 3), Color(0.95, 0.65, 0.15, 0.85), true)
	draw_rect(Rect2(-34, -7, 68, 3), Color(0.18, 0.20, 0.25, 1.0), true)
