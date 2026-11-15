extends Node2D
## Greenhouse level: builds the room, grow beds, machines, player and UI,
## then runs the survival / farming loop.

const BG_SCALE := 1.6
const ROOM_HALF := Vector2(837, 410)
const SPAWN := Vector2(0, 350)

# Planter racks: four beds on the left of the central tank, two on the right.
const BED_POSITIONS := [
	Vector2(-545, 110), Vector2(-545, 260),
	Vector2(-350, 110), Vector2(-350, 260),
	Vector2(390, 60), Vector2(390, 220),
]
# Machine placement: the beds, the central tank and the walls leave lanes only
# 44-58 px wider than the player, so the machines stand on open floor and do
# not carry a collision body (see Machine.gd) - they must never wall off a lane.
const COMPUTER_POS := Vector2(-300, -18)
const OXYGEN_POS := Vector2(490, 320)
const FUEL_POS := Vector2(-450, 330)

# Solid scenery: painted room walls plus the furniture (world coordinates).
const PROP_COLLIDERS := [
	# Room shell (the art has walls above the floor that must block).
	Rect2(-837, -410, 1674, 268),   # back wall band above the floor
	Rect2(-837, -410, 74, 820),     # left wall column
	Rect2(763, -410, 74, 820),      # right wall column
	Rect2(-837, 386, 1674, 24),     # bottom wall base
	# Furniture.
	Rect2(-517, -234, 432, 200),    # workbench / desk with monitors
	Rect2(-797, -178, 144, 248),    # left wall unit
	Rect2(-797, 118, 200, 272),     # bottom-left console
	Rect2(-221, -10, 448, 300),     # central hydroponics tank
	Rect2(523, -66, 168, 136),      # right console
	Rect2(587, 118, 160, 144),      # right cabinet
	Rect2(603, 102, 160, 288),      # bottom-right console
]

const O2_BREATH_DRAIN := 1.0
const O2_MACHINE_GAIN := 0.55
const POWER_SOLAR_GAIN := 1.2
const O2_MACHINE_POWER_COST := 0.7
const SUFFOCATION_DPS := 5.0

var player: CharacterBody2D
var camera: Camera2D
var hud
var ui

var beds: Array = []
var machines: Array = []
var _focus = null
var _autosave := 0.0
var _respawn_pending := false

func _ready() -> void:
	Global.ui_open = false
	if Global.player_hp <= 0.0:
		Global.player_hp = 100.0

	_build_background()
	_build_beds()
	_build_machines()
	_build_camera()
	_build_hud()
	_build_ui()
	_build_player()

	_apply_offline_growth()

	hud.toast("Keep the plants alive - they make your oxygen.")
	set_process(true)

# --- World -------------------------------------------------------------------
func _build_background() -> void:
	var tex := load(GameData.TEX_BG) as Texture2D
	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.texture = tex
	bg.centered = true
	bg.scale = Vector2(BG_SCALE, BG_SCALE)
	bg.z_index = -20
	add_child(bg)

	# Invisible walls around the room + solid furniture baked in the background.
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	for rect in [
		Rect2(-ROOM_HALF.x - 40, -ROOM_HALF.y - 40, ROOM_HALF.x * 2 + 80, 40),
		Rect2(-ROOM_HALF.x - 40, ROOM_HALF.y, ROOM_HALF.x * 2 + 80, 40),
		Rect2(-ROOM_HALF.x - 40, -ROOM_HALF.y, 40, ROOM_HALF.y * 2),
		Rect2(ROOM_HALF.x, -ROOM_HALF.y, 40, ROOM_HALF.y * 2),
	]:
		_add_box(walls, rect)
	# Desk, consoles and the central hydroponics tank are solid.
	for rect in PROP_COLLIDERS:
		_add_box(walls, rect)
	add_child(walls)

func _add_box(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = rect.size
	shape.shape = rs
	shape.position = rect.position + rect.size * 0.5
	body.add_child(shape)

func _build_beds() -> void:
	var script := preload("res://GrowBed.gd")
	for i in BED_POSITIONS.size():
		var bed := Node2D.new()
		bed.set_script(script)
		bed.name = "Bed%d" % i
		bed.position = BED_POSITIONS[i]
		bed.z_index = 0
		add_child(bed)
		bed.setup(i)
		beds.append(bed)

func _build_machines() -> void:
	# The shop uses the monitors already drawn on the workbench, so no extra
	# computer sprite is placed in the room.
	machines.append(_machine("computer", COMPUTER_POS))
	machines.append(_machine("oxygen", OXYGEN_POS))
	machines.append(_machine("fuel", FUEL_POS))

func _machine(kind: String, pos: Vector2) -> Node2D:
	var m := Node2D.new()
	m.set_script(preload("res://Machine.gd"))
	m.name = "Machine_" + kind
	m.position = pos
	add_child(m)
	m.setup(kind)
	return m

func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2(0.85, 0.85)
	camera.position_smoothing_enabled = true
	camera.limit_left = int(-ROOM_HALF.x)
	camera.limit_top = int(-ROOM_HALF.y)
	camera.limit_right = int(ROOM_HALF.x)
	camera.limit_bottom = int(ROOM_HALF.y)
	add_child(camera)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(preload("res://HUD.gd"))
	add_child(hud)

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.set_script(preload("res://UI.gd"))
	add_child(ui)
	ui.greenhouse = self

func _build_player() -> void:
	player = CharacterBody2D.new()
	player.name = "Player"
	player.set_script(preload("res://player.gd"))

	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.texture = load("res://Character.png") as Texture2D
	spr.scale = Vector2(0.14993763, 0.13387283)
	player.add_child(spr)

	var col := CollisionShape2D.new()
	col.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = 22.0
	col.shape = circle
	col.position = Vector2(0, 6)
	player.add_child(col)

	var spawn := SPAWN
	if Global.player_position != Vector2.ZERO and absf(Global.player_position.x) < ROOM_HALF.x and absf(Global.player_position.y) < ROOM_HALF.y:
		spawn = Global.player_position
	player.position = spawn
	player.z_index = 5
	# Hard limit: even a physics push-out can never leave the room.
	player.room_bounds = Rect2(-ROOM_HALF, ROOM_HALF * 2.0)
	add_child(player)
	player.died.connect(_on_player_died)

func _apply_offline_growth() -> void:
	var elapsed := Global.seconds_since_save()
	if elapsed < 5.0:
		return
	Global.apply_offline(elapsed)
	refresh_beds()
	var minutes := int(elapsed / 60.0)
	hud.toast("You were away %d min. Plants kept growing." % minutes)

# --- Loop --------------------------------------------------------------------
func _process(delta: float) -> void:
	if player == null:
		return
	# Do not let a long stall (window drag, shader compile) drain the bars.
	delta = minf(delta, 0.25)
	_update_focus()

	if Global.ui_open:
		return

	var o2_from_plants: float = Global.tick_beds(delta)

	# Power: solar panels recharge the battery.
	Global.power = min(Global.MAX_POWER, Global.power + POWER_SOLAR_GAIN * delta)

	# Oxygen concentrator.
	if Global.oxygen_machine_on and Global.power >= O2_MACHINE_POWER_COST * delta:
		Global.power -= O2_MACHINE_POWER_COST * delta
		Global.oxygen += O2_MACHINE_GAIN * delta

	# Plants produce oxygen.
	Global.oxygen += o2_from_plants * delta

	# The crew breathes.
	Global.oxygen = clampf(Global.oxygen - O2_BREATH_DRAIN * delta, 0.0, Global.MAX_OXYGEN)
	if Global.oxygen <= 0.0 and not _respawn_pending:
		player.take_damage(SUFFOCATION_DPS * delta)

	for bed in beds:
		bed.refresh()

	_autosave += delta
	if _autosave > 20.0:
		_autosave = 0.0
		_save()

func _update_focus() -> void:
	var best = null
	var best_dist := 130.0
	for bed in beds:
		var d: float = bed.global_position.distance_to(player.global_position)
		if d < best_dist:
			best_dist = d
			best = bed
	for m in machines:
		var d: float = m.global_position.distance_to(player.global_position)
		if d < best_dist:
			best_dist = d
			best = m
	_focus = best
	if hud:
		hud.set_prompt(best.prompt() if best else "")

# --- Input -------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if ui and ui.is_open():
			ui.close()
		return
	if ui and ui.is_open():
		return
	match event.keycode:
		KEY_E:
			_interact()
		KEY_TAB:
			ui.show_inventory()
		KEY_Q:
			eat_best()

func _interact() -> void:
	if _focus == null:
		return
	if _focus.get("index") != null:
		_interact_bed(_focus)
	else:
		_interact_machine(_focus)

func _interact_bed(bed) -> void:
	if bed.is_empty():
		ui.show_seed_picker(bed.index)
	elif bed.is_withered():
		Global.beds[bed.index] = {"plant": "", "progress": 0.0, "water": 0.0,
			"dry_time": 0.0, "withered": false, "planted_at": 0}
		bed.refresh(true)
		hud.toast("Removed the dead plant.")
	elif bed.is_mature():
		var got: Dictionary = Global.harvest(bed.index)
		if not got.is_empty():
			var data := GameData.plant(str(got["plant"]))
			hud.toast("Harvested %d x %s" % [int(got["count"]), str(data.get("name", "crop"))])
			bed.refresh(true)
	else:
		if Global.water_bed(bed.index):
			hud.toast("Watered. (-6 water)")
			bed.refresh(true)
		else:
			hud.toast("Not enough water in the tank.")

func _interact_machine(m) -> void:
	match m.kind:
		"computer":
			ui.show_shop()
		"oxygen":
			Global.oxygen_machine_on = not Global.oxygen_machine_on
			hud.toast("Oxygen maker %s" % ("ON" if Global.oxygen_machine_on else "OFF"))
			m.refresh()
		"fuel":
			ui.show_info("FUEL TANK",
				"Fuel %d / %d\n\nConvert harvest into fuel at the computer.\nReach %d fuel to power the rescue ship." % [
					roundi(Global.fuel), int(Global.MAX_FUEL), int(Global.MAX_FUEL)])

# --- Eating ------------------------------------------------------------------
func eat_item(item_id: String) -> void:
	var pid := GameData.crop_plant(item_id)
	if pid == "":
		return
	if not Global.take_item(item_id, 1):
		return
	var data := GameData.plant(pid)
	if player:
		player.heal(float(data.get("hp", 0.0)))
		player.eat()
	hud.toast("Ate %s  (+%d food)" % [str(data.get("name", "crop")), int(data.get("food", 0))])

func eat_best() -> void:
	var best_id := ""
	var best_food := -1.0
	for item_id in Global.inventory.keys():
		var pid := GameData.crop_plant(str(item_id))
		if pid == "":
			continue
		var f := float(GameData.plant(pid).get("food", 0.0))
		if f > best_food:
			best_food = f
			best_id = str(item_id)
	if best_id == "":
		hud.toast("Nothing to eat - harvest a crop first.")
		return
	eat_item(best_id)

# --- Death / respawn ---------------------------------------------------------
func _on_player_died() -> void:
	if _respawn_pending:
		return
	_respawn_pending = true
	await get_tree().create_timer(3.5).timeout
	_respawn_pending = false
	Global.player_hp = player.max_hp
	Global.player_food = player.max_food
	Global.oxygen = 55.0
	Global.player_position = SPAWN
	player.revive()
	player.global_position = SPAWN
	if camera:
		camera.global_position = SPAWN
	hud.toast("Life support rebooted. Keep the oxygen up!")

# --- Helpers -----------------------------------------------------------------
func refresh_beds() -> void:
	for bed in beds:
		bed.refresh(true)

func toast(text: String) -> void:
	if hud:
		hud.toast(text)

func _save() -> void:
	Global.player_position = player.global_position if player else SPAWN
	Global.current_scene = "res://greenhouse.tscn"
	Global.save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
