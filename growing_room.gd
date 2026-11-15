extends Node2D
## Khoang trồng cây trong tàu (growing module) — 10 khay 2x5.
##
## Được WorldController bật/tắt giống MarsMap: node nằm trong Game, giữ nguyên
## trạng thái SolSystem khi đi vào/ra. Toạ độ node = toạ độ ảnh nền 1280x640.
## Logic trồng/tưới/thu hoạch dùng chung Global.beds + GameData.

const TEX_BG := "res://assets/bg/greenhouse_growing.png"
const ROOM_SIZE := Vector2(1280.0, 640.0)
const SPAWN := Vector2(320.0, 470.0)
const DOOR_RECT := Rect2(58.0, 530.0, 140.0, 96.0)
const INTERACT_RADIUS := 110.0
const O2_FROM_PLANTS := 1.0   # nhân với tổng oxygen/s của cây trưởng thành

## Tâm 10 ô đất trong ảnh nền (2 hàng x 5 cột).
const BED_CENTERS: Array[Vector2] = [
	Vector2(394, 392), Vector2(516, 392), Vector2(638, 392), Vector2(760, 392), Vector2(882, 392),
	Vector2(394, 506), Vector2(516, 506), Vector2(638, 506), Vector2(760, 506), Vector2(882, 506),
]

var player: CharacterBody2D
var beds: Array = []
var ui

var _active := false
var _focus: Node2D = null
var _overlay: CanvasLayer = null
var _prompt: Label
var _toast_label: Label
var _hint_label: Label
var _toast_time := 0.0
var _refresh_clock := 0.0
var _saved_bounds := Rect2()
var _collision_state: Dictionary = {}


func _ready() -> void:
	z_index = -40
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	_register_interact_action()
	_build_background()
	_build_walls()
	_build_beds()
	_build_ui()
	_build_overlay()
	set_active(false)


# --- Dựng cảnh ---------------------------------------------------------------
func _register_interact_action() -> void:
	if InputMap.has_action("interact"):
		return
	InputMap.add_action("interact")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	InputMap.action_add_event("interact", ev)


func _build_background() -> void:
	var tex := load(TEX_BG) as Texture2D
	if tex == null:
		push_warning("GrowingRoom: thiếu ảnh nền " + TEX_BG)
		return
	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.texture = tex
	bg.centered = false
	bg.position = Vector2.ZERO
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.z_index = -100
	add_child(bg)


func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	add_child(body)
	# Tường trên (dải tường trong ảnh), hai bên và đáy.
	_add_wall(body, Rect2(0.0, 96.0, ROOM_SIZE.x, 26.0))
	_add_wall(body, Rect2(0.0, 96.0, 26.0, ROOM_SIZE.y - 96.0))
	_add_wall(body, Rect2(ROOM_SIZE.x - 26.0, 96.0, 26.0, ROOM_SIZE.y - 96.0))
	_add_wall(body, Rect2(0.0, ROOM_SIZE.y - 24.0, ROOM_SIZE.x, 24.0))


func _add_wall(body: StaticBody2D, rect: Rect2) -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.position + rect.size * 0.5
	body.add_child(cs)


func _build_beds() -> void:
	var bed_script := preload("res://GrowBed.gd")
	for i in BED_CENTERS.size():
		var bed := Node2D.new()
		bed.name = "Bed%d" % i
		bed.set_script(bed_script)
		# GrowBed vẽ hộp đất quanh gốc toạ độ, nên hạ xuống cho khớp ô đất trong ảnh.
		bed.position = BED_CENTERS[i] + Vector2(0.0, 26.0)
		add_child(bed)
		bed.setup(i)
		beds.append(bed)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Overlay"
	layer.layer = 5
	layer.visible = false
	add_child(layer)
	_overlay = layer

	_hint_label = _make_label(layer, Vector2(16, -110), HORIZONTAL_ALIGNMENT_LEFT, 14,
		"MODULE TRỒNG CÂY — E: trồng/tưới/thu hoạch   TAB: túi   G: về khoang chính")
	_prompt = _make_label(layer, Vector2(0, -54), HORIZONTAL_ALIGNMENT_CENTER, 20, "")
	_toast_label = _make_label(layer, Vector2(0, -92), HORIZONTAL_ALIGNMENT_CENTER, 17, "")
	_toast_label.modulate.a = 0.0


func _make_label(layer: CanvasLayer, offset_bottom: Vector2, align: int, size: int, text: String) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_left = -520
	label.offset_right = 520
	label.offset_top = offset_bottom.y - 30
	label.offset_bottom = offset_bottom.y
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.text = text
	layer.add_child(label)
	return label


# --- Bật/tắt (WorldController gọi) -------------------------------------------
func set_active(active: bool) -> void:
	_active = active
	visible = active
	set_process(active)
	set_process_unhandled_input(active)
	if _overlay != null:
		_overlay.visible = active
	if ui != null:
		ui.visible = false
	_set_collisions_enabled(active)
	if active:
		_player_lookup()
		if player != null:
			_saved_bounds = player.room_bounds
			player.room_bounds = Rect2(30.0, 120.0, ROOM_SIZE.x - 60.0, ROOM_SIZE.y - 150.0)
			player.z_index = 5
		_apply_camera_limits()
		refresh_beds()
		toast("Khoang trồng cây: %d khay. Cây trưởng thành nhả oxy." % beds.size())
	else:
		if player != null and is_instance_valid(player):
			player.room_bounds = _saved_bounds
		_focus = null
		if _prompt != null:
			_prompt.text = ""
		if _toast_label != null:
			_toast_label.modulate.a = 0.0


func spawn_point() -> Vector2:
	return SPAWN


func _set_collisions_enabled(enabled: bool) -> void:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject2D:
			var key := int(node.get_instance_id())
			if not _collision_state.has(key):
				_collision_state[key] = {"layer": node.collision_layer, "mask": node.collision_mask}
			var saved: Dictionary = _collision_state[key]
			node.collision_layer = int(saved["layer"]) if enabled else 0
			node.collision_mask = int(saved["mask"]) if enabled else 0
		for child in node.get_children():
			stack.append(child)


func _apply_camera_limits() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(ROOM_SIZE.x)
	camera.limit_bottom = int(ROOM_SIZE.y)
	camera.reset_smoothing()


func _player_lookup() -> void:
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null and get_tree().current_scene != null:
		player = get_tree().current_scene.find_child("Player", true, false) as CharacterBody2D


# --- Vòng chạy ---------------------------------------------------------------
func _process(delta: float) -> void:
	if not _active:
		return
	if player == null or not is_instance_valid(player):
		_player_lookup()
		if player == null:
			return

	# Cây lớn + nhả oxy (dùng chung logic với scene nhà kính cũ).
	var o2_rate: float = Global.tick_beds(delta)
	if o2_rate > 0.0:
		Global.oxygen = clampf(Global.oxygen + o2_rate * O2_FROM_PLANTS * delta, 0.0, Global.MAX_OXYGEN)

	_refresh_clock += delta
	if _refresh_clock >= 0.3:
		_refresh_clock = 0.0
		for bed in beds:
			bed.refresh(false)

	_update_focus()

	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time < 0.6:
			_toast_label.modulate.a = maxf(0.0, _toast_time / 0.6)


func _update_focus() -> void:
	var pos := player.global_position
	var best: Node2D = null
	var best_distance := INTERACT_RADIUS
	for bed in beds:
		var distance: float = pos.distance_to((bed as Node2D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = bed
	_focus = best
	if _prompt == null:
		return
	if best != null:
		_prompt.text = str(best.call("prompt"))
	elif DOOR_RECT.grow(20.0).has_point(to_local(pos)):
		_prompt.text = "[E] Về khoang chính"
	else:
		_prompt.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if ui != null and ui.has_method("is_open") and ui.is_open():
		if event.is_action_pressed("ui_cancel"):
			ui.close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB and ui != null:
			ui.show_inventory()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_G:
			get_viewport().set_input_as_handled()
			_leave()
			return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_interact()


func _interact() -> void:
	if player == null:
		return
	if _focus != null:
		_interact_bed(_focus)
	elif DOOR_RECT.grow(20.0).has_point(to_local(player.global_position)):
		_leave()


func _interact_bed(bed: Node2D) -> void:
	if bool(bed.call("is_empty")):
		if ui != null:
			ui.show_seed_picker(int(bed.get("index")))
	elif bool(bed.call("is_withered")):
		Global.beds[int(bed.get("index"))] = _empty_bed()
		bed.call("refresh", true)
		toast("Đã dọn cây chết.")
	elif bool(bed.call("is_mature")):
		var got: Dictionary = Global.harvest(int(bed.get("index")))
		if not got.is_empty():
			var data := GameData.plant(str(got["plant"]))
			toast("Thu hoạch %d x %s" % [int(got["count"]), str(data.get("name", "crop"))])
			bed.call("refresh", true)
	else:
		if Global.water_bed(int(bed.get("index"))):
			toast("Đã tưới. (-6 nước)")
			bed.call("refresh", true)
		else:
			toast("Không đủ nước trong bồn.")


func _empty_bed() -> Dictionary:
	return {"plant": "", "progress": 0.0, "water": 0.0, "dry_time": 0.0,
		"withered": false, "planted_at": 0}


func _leave() -> void:
	var controller := get_tree().current_scene.find_child("WorldController", true, false)
	if controller != null and controller.has_method("return_from_growing"):
		controller.call("return_from_growing")
		return
	# Dự phòng: tự tắt module nếu không tìm thấy WorldController.
	set_active(false)


# --- API cho UI.gd (seed picker dùng chung) ----------------------------------
func toast(text: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	_toast_time = 2.6


func refresh_beds() -> void:
	for bed in beds:
		bed.refresh(true)


func plant_seed(bed_index: int, plant_id: String) -> bool:
	if not Global.plant(bed_index, plant_id):
		return false
	refresh_beds()
	return true


# --- UI (túi đồ / chọn hạt) --------------------------------------------------
func _build_ui() -> void:
	if ui != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 20
	layer.set_script(preload("res://UI.gd"))
	add_child(layer)          # _ready của UI.gd chạy ở đây
	ui = layer
	ui.greenhouse = self


func _draw() -> void:
	# Cửa về khoang chính (không cần ảnh riêng).
	draw_rect(DOOR_RECT, Color(0.06, 0.09, 0.12, 0.85), true)
	draw_rect(DOOR_RECT, Color(0.35, 0.85, 1.0, 0.9), false, 3.0)
	draw_string(ThemeDB.fallback_font, DOOR_RECT.position + Vector2(14, 30),
		"◀ VỀ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.95, 1.0))
