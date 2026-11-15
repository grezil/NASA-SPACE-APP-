extends Node2D
class_name MarsExteriorMap
## Demo Mars map: exactly 3 activities.
## 1) Geology Lab: research a sample and prepare a report.
## 2) Solar Array: clean dust and restore power generation.
## 3) NASA Data Relay: send the report and receive a reward.
## Attach to MarsMap, a sibling of Room and Player in Game.tscn.

signal location_interacted(location_id: String)

@export_group("Kích thước bản đồ")
@export var map_width := 2400.0
@export var map_height := 900.0
@export var build_boundary_collisions := true
@export var apply_camera_limits := true

@export_group("Tương tác")
@export var player_group := "player"
@export var interact_action := "interact"
@export var interaction_radius := 125.0
@export var show_debug_zones := false
@export var start_active := false

@export_group("Ảnh đồ họa Mars")
@export var mars_background_texture: Texture2D
@export var geology_lab_texture: Texture2D
@export var solar_array_texture: Texture2D
@export var communications_relay_texture: Texture2D

@export_group("Vị trí và kích thước")
@export var geology_lab_sprite_position := Vector2(-420.0, -35.0)
@export var geology_lab_sprite_size := Vector2(300.0, 190.0)
@export var solar_array_sprite_position := Vector2(180.0, -220.0)
@export var solar_array_sprite_size := Vector2(360.0, 210.0)
@export var communications_relay_sprite_position := Vector2(820.0, 75.0)
@export var communications_relay_sprite_size := Vector2(210.0, 230.0)

const GROUND := Color(0.43, 0.25, 0.18, 1.0)
const GROUND_DARK := Color(0.31, 0.18, 0.14, 1.0)
const GROUND_LIGHT := Color(0.57, 0.35, 0.24, 1.0)
const METAL := Color(0.68, 0.72, 0.74, 1.0)
const METAL_DARK := Color(0.20, 0.27, 0.32, 1.0)
const PANEL_BLUE := Color(0.08, 0.22, 0.38, 1.0)
const PANEL_GLOW := Color(0.28, 0.72, 0.92, 1.0)
const HIGHLIGHT := Color(1.0, 0.78, 0.28, 1.0)

var _player: Node2D
var _points: Array[Dictionary] = []
var _focused_id := ""
var _hint_layer: CanvasLayer
var _hint_label: Label
var _terrain_marks: Array[Dictionary] = []
var _collision_bodies: Array[StaticBody2D] = []


func _ready() -> void:
	z_index = -50
	_register_interact_action()
	_auto_find_textures()
	_build_art_sprites()
	_build_points()
	_generate_terrain_marks()
	if build_boundary_collisions:
		_build_boundaries()
		_build_equipment_collisions()
	_build_hint()
	set_active(start_active)
	queue_redraw()


func set_active(active: bool) -> void:
	visible = active
	set_process(active)
	set_process_unhandled_input(active)
	for body in _collision_bodies:
		if is_instance_valid(body):
			body.collision_layer = 1 if active else 0
			body.collision_mask = 0
	if not active:
		_focused_id = ""
		if _hint_label != null:
			_hint_label.visible = false
	else:
		call_deferred("_apply_camera_limits")
	queue_redraw()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		if _hint_label != null:
			_hint_label.visible = false
		return

	var player_pos := to_local(_player.global_position)
	var best_id := ""
	var best_distance := INF
	for point in _points:
		var distance: float = player_pos.distance_to(point["position"])
		if distance <= float(point["radius"]) and distance < best_distance:
			best_distance = distance
			best_id = str(point["id"])

	if best_id != _focused_id:
		_focused_id = best_id
		queue_redraw()

	if _hint_label == null:
		return
	if _focused_id == "":
		_hint_label.visible = false
	else:
		var point := _get_point(_focused_id)
		_hint_label.text = "[E]  %s  —  %s" % [str(point["name"]), str(point["hint"])]
		_hint_label.visible = true
		_layout_hint()


func _unhandled_input(event: InputEvent) -> void:
	if _focused_id == "":
		return
	if event.is_action_pressed(interact_action):
		get_viewport().set_input_as_handled()
		_interact_with_point(_focused_id)


func _auto_find_textures() -> void:
	mars_background_texture = _pick_texture(mars_background_texture, [
		"res://assets/mars/Mars_Background.png", "res://Mars_Background.png"])
	geology_lab_texture = _pick_texture(geology_lab_texture, [
		"res://assets/mars/Geology_Lab.png", "res://Geology_Lab.png"])
	solar_array_texture = _pick_texture(solar_array_texture, [
		"res://assets/mars/Solar_Array.png", "res://Solar_Array.png"])
	communications_relay_texture = _pick_texture(communications_relay_texture, [
		"res://assets/mars/Communications_Relay.png", "res://Communications_Relay.png"])


func _pick_texture(current: Texture2D, paths: Array) -> Texture2D:
	if current != null:
		return current
	for path in paths:
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


func _build_art_sprites() -> void:
	if mars_background_texture != null:
		var bg := Sprite2D.new()
		bg.name = "MarsBackgroundSprite"
		bg.texture = mars_background_texture
		bg.centered = true
		bg.position = Vector2.ZERO
		# Khớp chính xác biên bản đồ để ảnh không lòi ra ngoài camera/boundary.
		# Nên dùng background 2400x900 (tỷ lệ 8:3) để không bị méo.
		var texture_size := Vector2(mars_background_texture.get_width(), mars_background_texture.get_height())
		var target_aspect := map_width / maxf(map_height, 1.0)
		var texture_aspect := texture_size.x / maxf(texture_size.y, 1.0)
		if absf(texture_aspect - target_aspect) > 0.03:
			push_warning("MarsMap: background nên có tỷ lệ %.3f (%.0fx%.0f) để khớp map, ảnh hiện tại %.3f." % [target_aspect, map_width, map_height, texture_aspect])
		bg.scale = Vector2(map_width / texture_size.x, map_height / texture_size.y)
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg.z_index = -100
		add_child(bg)

	if geology_lab_texture != null:
		_add_art_sprite("GeologyLabSprite", geology_lab_texture, geology_lab_sprite_position, geology_lab_sprite_size, 0)
	if solar_array_texture != null:
		_add_art_sprite("SolarArraySprite", solar_array_texture, solar_array_sprite_position, solar_array_sprite_size, 0)
	if communications_relay_texture != null:
		_add_art_sprite("CommunicationsRelaySprite", communications_relay_texture, communications_relay_sprite_position, communications_relay_sprite_size, 0)


func _add_art_sprite(node_name: String, texture: Texture2D, position_2d: Vector2, target_size: Vector2, layer: int) -> void:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.centered = true
	sprite.position = position_2d
	sprite.scale = Vector2(target_size.x / texture.get_width(), target_size.y / texture.get_height())
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = layer
	add_child(sprite)


func _build_points() -> void:
	_points = [
		{
			"id": "research",
			"name": "Geology Lab / Nghiên cứu",
			"hint": "Phân tích mẫu đá và tạo báo cáo khoa học",
			"position": Vector2(-420.0, 105.0),
			"radius": interaction_radius,
			"action": "_start_mars_research",
		},
		{
			"id": "solar_cleaning",
			"name": "Solar Array / Vệ sinh pin",
			"hint": "Lau bụi để phục hồi hiệu suất phát điện",
			"position": Vector2(180.0, -65.0),
			"radius": 150.0,
			"action": "_clean_mars_solar_panels",
		},
		{
			"id": "nasa_relay",
			"name": "NASA Data Relay / Gửi báo cáo",
			"hint": "Gửi dữ liệu nghiên cứu về NASA để nhận thưởng",
			"position": Vector2(820.0, 220.0),
			"radius": 145.0,
			"action": "_send_mars_research_to_nasa",
		},
	]


func _get_point(point_id: String) -> Dictionary:
	for point in _points:
		if str(point["id"]) == point_id:
			return point
	return {}


func _interact_with_point(point_id: String) -> void:
	var point := _get_point(point_id)
	if point.is_empty():
		return
	var system := _find_sol_system()
	if system == null:
		_show_hint_error("Không tìm thấy SolSystem. Hãy giữ Room/sol_system.gd trong scene Game.")
		return
	var method_name := str(point["action"])
	if not system.has_method(method_name):
		_show_hint_error("SolSystem chưa có hàm %s. Hãy thay sol_system.gd bằng bản demo mới." % method_name)
		return
	system.call(method_name)
	location_interacted.emit(point_id)


func _find_player() -> Node2D:
	var found := get_tree().get_first_node_in_group(player_group) as Node2D
	if found == null and get_tree().current_scene != null:
		found = get_tree().current_scene.find_child("Player", true, false) as Node2D
	return found


func _find_sol_system() -> Node:
	if get_tree().current_scene == null:
		return null
	return _find_sol_system_recursive(get_tree().current_scene)


func _find_sol_system_recursive(parent: Node) -> Node:
	for child in parent.get_children():
		if child.has_method("_start_mars_research") and child.has_method("_clean_mars_solar_panels"):
			return child
		var nested := _find_sol_system_recursive(child)
		if nested != null:
			return nested
	return null


func _show_hint_error(message: String) -> void:
	if _hint_label != null:
		_hint_label.text = message
		_hint_label.visible = true


func _register_interact_action() -> void:
	if not InputMap.has_action(interact_action):
		InputMap.add_action(interact_action)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = KEY_E
	if not InputMap.action_has_event(interact_action, key_event):
		InputMap.action_add_event(interact_action, key_event)


func _build_hint() -> void:
	_hint_layer = CanvasLayer.new()
	_hint_layer.layer = 30
	_hint_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hint_layer)
	_hint_label = Label.new()
	_hint_label.name = "InteractionHint"
	_hint_label.visible = false
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color.WHITE)
	_hint_label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.07, 1.0))
	_hint_label.add_theme_constant_override("outline_size", 6)
	_hint_layer.add_child(_hint_label)
	get_viewport().size_changed.connect(_layout_hint)
	_layout_hint()


func _layout_hint() -> void:
	if _hint_label == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var width := maxf(1.0, viewport_size.x - 24.0)
	var height := 54.0 if viewport_size.x >= 640.0 else 68.0
	_hint_label.position = Vector2((viewport_size.x - width) * 0.5, viewport_size.y - height - 10.0)
	_hint_label.size = Vector2(width, height)
	_hint_label.add_theme_font_size_override("font_size", int(clampf(viewport_size.x / 55.0, 13.0, 18.0)))


func _generate_terrain_marks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 481516
	for i in range(145):
		_terrain_marks.append({
			"position": Vector2(rng.randf_range(-map_width * 0.48, map_width * 0.48), rng.randf_range(-map_height * 0.46, map_height * 0.46)),
			"radius": rng.randf_range(2.0, 11.0),
			"light": rng.randf() > 0.5,
		})


func _build_boundaries() -> void:
	var thickness := 70.0
	_add_collision_box(Vector2(0.0, -map_height * 0.5 - thickness * 0.5), Vector2(map_width + thickness * 2.0, thickness))
	_add_collision_box(Vector2(0.0, map_height * 0.5 + thickness * 0.5), Vector2(map_width + thickness * 2.0, thickness))
	_add_collision_box(Vector2(-map_width * 0.5 - thickness * 0.5, 0.0), Vector2(thickness, map_height + thickness * 2.0))
	_add_collision_box(Vector2(map_width * 0.5 + thickness * 0.5, 0.0), Vector2(thickness, map_height + thickness * 2.0))


func _build_equipment_collisions() -> void:
	# Geology Lab and NASA relay block walking through their solid bases.
	# Interaction points remain just in front of these colliders.
	_add_collision_box(Vector2(-420.0, -35.0), Vector2(260.0, 100.0))
	_add_collision_box(Vector2(820.0, 75.0), Vector2(90.0, 90.0))
	# Solar panels are flat ground equipment, so they intentionally have no solid collider.


func _add_collision_box(pos: Vector2, box_size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	_collision_bodies.append(body)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = box_size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)


func _apply_camera_limits() -> void:
	if not apply_camera_limits:
		return
	await get_tree().process_frame
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var top_left := to_global(Vector2(-map_width * 0.5, -map_height * 0.5))
	var bottom_right := to_global(Vector2(map_width * 0.5, map_height * 0.5))
	camera.limit_left = int(top_left.x)
	camera.limit_top = int(top_left.y)
	camera.limit_right = int(bottom_right.x)
	camera.limit_bottom = int(bottom_right.y)
	camera.reset_smoothing()


func _draw() -> void:
	if mars_background_texture == null:
		draw_rect(Rect2(-map_width * 0.5, -map_height * 0.5, map_width, map_height), GROUND)
		for mark in _terrain_marks:
			var color: Color = GROUND_LIGHT if bool(mark["light"]) else GROUND_DARK
			draw_circle(mark["position"], float(mark["radius"]), color)
		_draw_paths()
		_draw_craters()

	if geology_lab_texture == null:
		_draw_research_lab()
	if solar_array_texture == null:
		_draw_solar_array()
	if communications_relay_texture == null:
		_draw_nasa_relay()
	_draw_points()


func _draw_paths() -> void:
	var path := PackedVector2Array([
		Vector2(-1050.0, 300.0), Vector2(-760.0, 180.0), Vector2(-420.0, 105.0),
		Vector2(-120.0, -10.0), Vector2(180.0, -65.0), Vector2(480.0, 60.0), Vector2(820.0, 220.0),
	])
	draw_polyline(path, Color(0.67, 0.42, 0.29, 0.95), 42.0, true)
	draw_polyline(path, Color(0.76, 0.52, 0.36, 0.28), 5.0, true)


func _draw_research_lab() -> void:
	var rect := Rect2(-565.0, -135.0, 290.0, 185.0)
	draw_rect(rect, METAL, true)
	draw_rect(rect, METAL_DARK, false, 7.0)
	draw_rect(Rect2(-525.0, -100.0, 85.0, 55.0), PANEL_BLUE, true)
	draw_rect(Rect2(-525.0, -100.0, 85.0, 55.0), PANEL_GLOW, false, 3.0)
	draw_rect(Rect2(-420.0, -102.0, 105.0, 62.0), Color(0.34, 0.39, 0.42), true)
	draw_rect(Rect2(-420.0, -102.0, 105.0, 62.0), METAL_DARK, false, 3.0)
	_draw_world_text(Vector2(-420.0, -155.0), "GEOLOGY LAB", 22, Color.WHITE)


func _draw_solar_array() -> void:
	for row in range(2):
		for col in range(3):
			var pos := Vector2(20.0 + col * 112.0, -330.0 + row * 92.0)
			var rect := Rect2(pos, Vector2(94.0, 72.0))
			draw_rect(rect, PANEL_BLUE, true)
			draw_rect(rect, Color(0.38, 0.66, 0.82), false, 3.0)
			for line_i in range(1, 4):
				draw_line(pos + Vector2(line_i * 23.5, 0.0), pos + Vector2(line_i * 23.5, 72.0), Color(0.31, 0.55, 0.72), 1.5)
			draw_line(pos + Vector2(0.0, 36.0), pos + Vector2(94.0, 36.0), Color(0.31, 0.55, 0.72), 1.5)
	_draw_world_text(Vector2(185.0, -350.0), "SOLAR ARRAY", 22, Color.WHITE)


func _draw_nasa_relay() -> void:
	var center := Vector2(820.0, 75.0)
	draw_circle(center, 75.0, Color(0.38, 0.43, 0.47))
	draw_arc(center, 75.0, 0.0, TAU, 40, METAL_DARK, 5.0, true)
	draw_circle(center, 48.0, Color(0.65, 0.72, 0.75))
	draw_arc(center, 48.0, 0.0, TAU, 40, Color(0.16, 0.22, 0.27), 4.0, true)
	draw_circle(center, 13.0, PANEL_GLOW)
	draw_line(center + Vector2(0.0, 48.0), center + Vector2(0.0, 112.0), METAL_DARK, 9.0)
	draw_rect(Rect2(780.0, 175.0, 80.0, 55.0), METAL, true)
	draw_rect(Rect2(780.0, 175.0, 80.0, 55.0), METAL_DARK, false, 4.0)
	draw_rect(Rect2(798.0, 190.0, 44.0, 20.0), PANEL_BLUE, true)
	_draw_world_text(Vector2(820.0, 275.0), "NASA DATA RELAY", 20, Color.WHITE)


func _draw_craters() -> void:
	for crater in [
		{"p": Vector2(-950.0, -265.0), "r": 58.0},
		{"p": Vector2(530.0, 330.0), "r": 65.0},
		{"p": Vector2(1060.0, -285.0), "r": 48.0},
		{"p": Vector2(-120.0, 330.0), "r": 34.0},
	]:
		var p: Vector2 = crater["p"]
		var radius: float = crater["r"]
		draw_circle(p, radius, Color(0.30, 0.18, 0.14, 0.8))
		draw_arc(p, radius, 0.0, TAU, 36, Color(0.64, 0.39, 0.28, 0.9), 5.0, true)


func _draw_points() -> void:
	for point in _points:
		var pos: Vector2 = point["position"]
		var focused := str(point["id"]) == _focused_id
		var color := HIGHLIGHT if focused else Color(0.85, 0.92, 0.96, 0.65)
		draw_circle(pos, 7.0, color)
		draw_arc(pos, 30.0, 0.0, TAU, 32, color, 3.0 if focused else 2.0, true)
		if show_debug_zones:
			draw_arc(pos, float(point["radius"]), 0.0, TAU, 48, Color(0.2, 1.0, 1.0, 0.85), 2.0, true)


func _draw_world_text(pos: Vector2, text_value: String, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	draw_string_outline(font, pos, text_value, HORIZONTAL_ALIGNMENT_CENTER, -1.0, size, 4, Color(0.08, 0.06, 0.05, 0.95))
	draw_string(font, pos, text_value, HORIZONTAL_ALIGNMENT_CENTER, -1.0, size, color)
