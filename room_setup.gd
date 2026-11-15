extends Node2D
## room_setup.gd: dựng cả căn phòng chỉ bằng 1 script.
##  - Ảnh nền tự phóng to cho phủ màn hình
##  - 3 thiết bị tương tác (máy tính, TRẠM THỰC PHẨM, bình nhiên liệu), đặt đúng chỗ trong ảnh nền
##  - Lại gần thiết bị: viền vàng nhấp nháy + chữ "[E] Tên thiết bị" => biết đang chọn đúng thiết bị nào
##  - Bấm E: nháy XANH nếu dùng được, nháy ĐỎ + rung nếu chưa dùng được
##  - Tường vô hình bám theo hình dạng sàn thật của ảnh nền (đi được cả phần sàn phía trên bên phải)
##  - Camera không lòi ra ngoài nền
##
## Cách dùng: thêm 1 node Node2D tên "Room" vào scene game, gắn script này,
## rồi kéo 4 ảnh vào các ô trong Inspector.

const OUTLINE_SHADER := """
shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 0.9, 0.25, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float n = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	n = max(n, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	n = max(n, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	n = max(n, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	float edge = (1.0 - tex.a) * n * strength;
	vec3 body = mix(tex.rgb + vec3(strength * 0.08), flash_color.rgb, flash * 0.55);
	COLOR = vec4(mix(body, outline_color.rgb, edge), max(tex.a, edge));
}
"""

# Danh sách cây trồng trong không gian (theo file Plants List):
#   Cây lương thực -> nhiều FOOD | Rau quả tươi -> vừa | Rau lá & thảo mộc -> ít FOOD nhưng hồi thêm HP
const CROPS := [
	{"name": "Khoai tây", "food": 30.0, "hp": 0.0},
	{"name": "Lúa mì lùn", "food": 28.0, "hp": 0.0},
	{"name": "Đậu nành", "food": 28.0, "hp": 0.0},
	{"name": "Cà chua bi", "food": 18.0, "hp": 2.0},
	{"name": "Ớt", "food": 12.0, "hp": 2.0},
	{"name": "Dâu tây", "food": 18.0, "hp": 3.0},
	{"name": "Cải mizuna", "food": 12.0, "hp": 4.0},
	{"name": "Xà lách romaine đỏ", "food": 12.0, "hp": 4.0},
	{"name": "Húng quế", "food": 8.0, "hp": 3.0},
	{"name": "Thì là", "food": 8.0, "hp": 3.0},
]

@export_group("Hình ảnh")
@export var background: Texture2D
@export var computer: Texture2D
@export var food_station: Texture2D
@export var fuel_container: Texture2D

@export_group("Phòng")
## Đường viền vùng sàn đi được, tính theo pixel của ảnh nền gốc (320x160). Mỗi điểm là 1 góc.
@export var walk_polygon := PackedVector2Array([
	Vector2(8, 153), Vector2(8, 92), Vector2(36, 92), Vector2(36, 78),
	Vector2(66, 78), Vector2(66, 84), Vector2(172, 84), Vector2(172, 61),
	Vector2(247, 60), Vector2(247, 58), Vector2(276, 58), Vector2(276, 99),
	Vector2(313, 99), Vector2(313, 153),
])
## Chỗ nhân vật xuất hiện, cũng theo pixel của ảnh nền gốc.
@export var player_spawn := Vector2(60, 115)
@export var move_player_to_spawn := true
@export var build_walls := true
@export var limit_camera := true

@export_group("Tương tác")
@export var interact_distance := 100.0
@export var highlight_color := Color(1.0, 0.9, 0.25)

@export_group("Gỡ lỗi")
## Hiện khung vàng (thiết bị), khung xanh lơ (tầm bấm E), đường xanh lá (vùng đi được)
## và dòng trạng thái ở góc dưới trái. Mặc định TẮT. Khi đang chạy game, bấm F3 để bật/tắt.
@export var debug_overlay := false

var _devices: Array = []
var _focused = null
var _player: Node2D
var _shader: Shader
var _scale := 1.0
var _origin := Vector2.ZERO
var _bg_size := Vector2.ZERO
var _bounds := Rect2()
var _debug_label: Label
var _debug_layer: CanvasLayer
var _debug_canvas: Node2D


func _ready() -> void:
	_register_input()
	_auto_find_textures()
	if background == null:
		push_warning("Room: không tìm thấy ảnh nền, hãy kéo backgroundfix.png vào ô Background")
		return

	_shader = Shader.new()
	_shader.code = OUTLINE_SHADER

	_build_background()
	_build_walls()

	# _add_device(ảnh, tên, hồi HP, hồi FOOD, chữ khi dùng, thời gian chờ, danh sách vật phẩm, chữ khi không cần)
	_add_device(computer, "Máy tính", 0.0, 0.0, "Máy tính đang hoạt động", 2.0, [], "")
	# Tham số cuối = nới thêm tầm bấm E (pixel) ở "mặt chính": Vector4(trái, trên, phải, dưới)
	# Trạm thực phẩm: mặt chính có màn hình xanh dương ở phía TRÁI (và hơi xuống dưới)
	_add_device(food_station, "Trạm thực phẩm", 0.0, 0.0, "", 4.0, CROPS, "Đã no rồi", Vector4(120, 0, 0, 60))
	# Bình nhiên liệu: mặt sau (hướng về máy tính) ở phía TRÊN
	_add_device(fuel_container, "Bình nhiên liệu", 0.0, 0.0, "Đã lấy nhiên liệu", 5.0, [], "", Vector4(0, 90, 0, 0))
	_add_device(fuel_container, "Bình nhiên liệu", 0.0, 0.0, "Đã lấy nhiên liệu", 5.0, [], "", Vector4(0, 90, 0, 0))

	# ===== DÁN 3 DÒNG NÀY =====
	var sol_system := SolSystem.new()
	add_child(sol_system)
	sol_system.bind(_devices)
	# ==========================

	if move_player_to_spawn:
		_move_player_to_spawn()
	if move_player_to_spawn:
		_move_player_to_spawn()
	if limit_camera:
		_limit_camera()
	_setup_debug()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		_set_debug("[DEBUG] KHÔNG TÌM THẤY Player. Node Player cần gắn player.gd mới nhất.")
		return

	var p := to_local(_player.global_position)
	var fv := _facing_vector()
	var best = null
	var best_score := INF
	for d in _devices:
		d.update_depth(p)
		# Vùng bấm E là khung vuông bao quanh thiết bị (+ phần nới ở mặt chính): đứng TRÊN / DƯỚI / TRÁI / PHẢI đều được
		if d.zone(interact_distance).has_point(p):
			var score: float = d.distance_to(p)
			# Đang quay mặt về phía thiết bị nào thì ưu tiên thiết bị đó (khi 2 máy nằm sát nhau)
			var to_dev: Vector2 = d.closest_point(p) - p
			if to_dev.length() > 1.0:
				score -= to_dev.normalized().dot(fv) * 80.0
			if score < best_score:
				best_score = score
				best = d

	_focused = best
	for d in _devices:
		d.focused = (d == best)

	if debug_overlay:
		var lines := PackedStringArray()
		lines.append("[DEBUG] Player OK | thiết bị đã dựng: %d/3 | hướng nhìn: %s | viền vàng sáng thì bấm E" % [_devices.size(), str(_player.get("facing"))])
		lines.append("  Khung VÀNG = thiết bị | XANH LƠ = tầm bấm E (cả 4 phía) | XANH LÁ = vùng đi được")
		for d in _devices:
			var mark := "   <== ĐANG CHỌN" if d == best else ""
			lines.append("  %s: cách %d px%s" % [d.device_name, int(d.distance_to(p)), mark])
		_set_debug("\n".join(lines))


func _find_player() -> Node2D:
	var found := get_tree().get_first_node_in_group("player") as Node2D
	if found == null and get_tree().current_scene != null:
		found = get_tree().current_scene.find_child("Player", true, false) as Node2D
	return found


func _facing_vector() -> Vector2:
	match str(_player.get("facing")):
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
	return Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		debug_overlay = not debug_overlay
		if _debug_layer != null:
			_debug_layer.visible = debug_overlay
		if _debug_canvas != null:
			_debug_canvas.visible = debug_overlay
			_debug_canvas.queue_redraw()
		return
	if event.is_action_pressed("interact") and _focused != null and _player != null:
		_focused.interact(_player)


# ---------- Tự tìm ảnh + gỡ lỗi ----------

## Ô nào trong Inspector còn trống thì tự tìm ảnh theo tên file trong res:// (và vài thư mục thường dùng).
func _auto_find_textures() -> void:
	background = _pick(background, ["backgroundfix.png"])
	computer = _pick(computer, ["Sinh_sComputer.png"])
	food_station = _pick(food_station, ["food_station.png", "Oxygenconcentrator.png"])
	fuel_container = _pick(fuel_container, ["Fuelcontainer.png"])
	if computer == null:
		push_warning("Room: thiếu ảnh Computer (Sinh_sComputer.png)")
	if food_station == null:
		push_warning("Room: thiếu ảnh Food Station (food_station.png hoặc Oxygenconcentrator.png)")
	if fuel_container == null:
		push_warning("Room: thiếu ảnh Fuel Container (Fuelcontainer.png)")


func _pick(current: Texture2D, names: Array) -> Texture2D:
	if current != null:
		return current
	for folder in ["res://", "res://art/", "res://assets/", "res://images/"]:
		for n in names:
			var path: String = folder + n
			if ResourceLoader.exists(path):
				return load(path) as Texture2D
	return null


func _setup_debug() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.visible = debug_overlay
	_debug_layer = layer
	_debug_label = Label.new()
	_debug_label.position = Vector2(12.0, get_viewport_rect().size.y - 125.0)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_debug_label)
	add_child(layer)

	_debug_canvas = Node2D.new()
	_debug_canvas.z_index = 100
	_debug_canvas.visible = debug_overlay
	_debug_canvas.draw.connect(_draw_debug)
	add_child(_debug_canvas)
	_debug_canvas.queue_redraw()


func _draw_debug() -> void:
	for d in _devices:
		_debug_canvas.draw_rect(d.rect, Color(1.0, 1.0, 0.0, 0.9), false, 2.0)
		_debug_canvas.draw_rect(d.zone(interact_distance), Color(0.0, 1.0, 1.0, 0.5), false, 2.0)
	if build_walls and walk_polygon.size() >= 3:
		var pts := PackedVector2Array()
		for q in walk_polygon:
			pts.append(_origin + q * _scale)
		pts.append(pts[0])
		_debug_canvas.draw_polyline(pts, Color(0.0, 1.0, 0.0, 0.8), 2.0)


func _set_debug(t: String) -> void:
	if _debug_label != null:
		_debug_label.text = t


# ---------- Dựng phòng ----------

func _build_background() -> void:
	var vp := get_viewport_rect().size
	_bg_size = background.get_size()
	# Phóng cho phủ kín màn hình, căn giữa (phần thừa bị cắt)
	_scale = maxf(vp.x / _bg_size.x, vp.y / _bg_size.y)
	_origin = vp * 0.5 - _bg_size * _scale * 0.5
	_bounds = Rect2(_origin, _bg_size * _scale)

	var spr := Sprite2D.new()
	spr.texture = background
	spr.centered = false
	spr.position = _origin
	spr.scale = Vector2(_scale, _scale)
	spr.z_index = -100
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(spr)


func _build_walls() -> void:
	if not build_walls or walk_polygon.size() < 3:
		return
	var pts := PackedVector2Array()
	for p in walk_polygon:
		pts.append(_origin + p * _scale)
	var body := StaticBody2D.new()
	var poly := CollisionPolygon2D.new()
	poly.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	poly.polygon = pts
	body.add_child(poly)
	add_child(body)


func _add_device(tex: Texture2D, dname: String, heal: float, food: float, msg: String,
		cd: float, items: Array, not_needed: String, extra := Vector4.ZERO) -> void:
	if tex == null:
		return
	var d := Device.new()
	d.device_name = dname
	d.heal_amount = heal
	d.food_amount = food
	d.message = msg
	d.cooldown = cd
	d.items = items
	d.extra = extra
	if not_needed != "":
		d.not_needed_text = not_needed
	d.setup(tex, _shader, _origin, _scale, highlight_color, _bounds)
	add_child(d)
	_devices.append(d)


func _move_player_to_spawn() -> void:
	await get_tree().process_frame
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null:
		p.global_position = to_global(_origin + player_spawn * _scale)


func _limit_camera() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var tl := to_global(_bounds.position)
	var br := to_global(_bounds.end)
	cam.limit_left = int(tl.x)
	cam.limit_top = int(tl.y)
	cam.limit_right = int(br.x)
	cam.limit_bottom = int(br.y)
	cam.reset_smoothing()


func _register_input() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	if not InputMap.action_has_event("interact", ev):
		InputMap.action_add_event("interact", ev)


# ---------- Một thiết bị tương tác ----------

class Device extends Node2D:
	signal used(device: Node2D, player: Node)

	var device_name := ""
	var heal_amount := 0.0
	var food_amount := 0.0
	var message := ""
	var cooldown := 5.0
	var items: Array = []        # nếu có: mỗi lần dùng nhận 1 vật phẩm {name, food, hp}
	var not_needed_text := "Không cần dùng lúc này"
	var rect := Rect2()          # vùng thiết bị (toạ độ của Room)
	var extra := Vector4.ZERO    # nới thêm tầm bấm E: (trái, trên, phải, dưới)
	var focused := false         # Room bật cờ này cho thiết bị gần nhất

	var _sprite: Sprite2D
	var _mat: ShaderMaterial
	var _prompt: Label
	var _base_pos := Vector2.ZERO
	var _bounds := Rect2()
	var _solid_top := 0.0
	var _glow := 0.0
	var _time := 0.0
	var _cooldown_left := 0.0
	var _see_through := false
	var _alpha := 1.0
	var _bag: Array = []
	var _flash_tween: Tween
	var _shake_tween: Tween


	func setup(tex: Texture2D, shader: Shader, origin: Vector2, scl: float, outline: Color, bounds: Rect2) -> void:
		_bounds = bounds
		_base_pos = origin

		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.centered = false
		_sprite.position = origin
		_sprite.scale = Vector2(scl, scl)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_mat = ShaderMaterial.new()
		_mat.shader = shader
		_mat.set_shader_parameter("outline_color", outline)
		_sprite.material = _mat
		add_child(_sprite)

		# Tìm phần ảnh thật sự có pixel (bỏ phần trong suốt) để làm vùng tương tác
		var used_px := Rect2(Vector2.ZERO, tex.get_size())
		var img := tex.get_image()
		if img != null:
			var r := img.get_used_rect()
			if r.size.x > 0 and r.size.y > 0:
				used_px = Rect2(r)
		rect = Rect2(origin + used_px.position * scl, used_px.size * scl)

		# Phần thân dưới của thiết bị chặn nhân vật đi xuyên qua
		_solid_top = rect.position.y + rect.size.y * 0.45
		var solid := Rect2(rect.position.x, _solid_top, rect.size.x, rect.end.y - _solid_top)
		var body := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = solid.size
		cs.shape = sh
		cs.position = solid.get_center()
		body.add_child(cs)
		add_child(body)

		# Dòng gợi ý phía trên thiết bị
		_prompt = _make_label("[E] " + device_name, Color.WHITE, rect.position.y - 34.0)
		_prompt.modulate.a = 0.0
		add_child(_prompt)


	# Vùng bấm E: khung bao quanh thiết bị, nới thêm ở "mặt chính" nếu có
	func zone(base: float) -> Rect2:
		var r := rect.grow(base)
		r.position -= Vector2(extra.x, extra.y)
		r.size += Vector2(extra.x + extra.z, extra.y + extra.w)
		return r


	func closest_point(p: Vector2) -> Vector2:
		return Vector2(
			clampf(p.x, rect.position.x, rect.end.x),
			clampf(p.y, rect.position.y, rect.end.y))


	# Khoảng cách tới mép thiết bị gần nhất (0 nếu đang đứng trong vùng thiết bị)
	func distance_to(p: Vector2) -> float:
		return p.distance_to(closest_point(p))


	# Nhân vật đứng phía sau thiết bị thì thiết bị che nhân vật, đứng phía trước thì ngược lại
	func update_depth(p: Vector2) -> void:
		var behind := p.y < _solid_top
		_sprite.z_index = 1 if behind else -1
		# Đứng phía sau thiết bị: làm thiết bị mờ đi để vẫn thấy nhân vật
		_see_through = behind and rect.has_point(p)


	func _process(delta: float) -> void:
		_time += delta
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
		_glow = move_toward(_glow, 1.0 if focused else 0.0, delta * 8.0)

		var pulse := 0.8 + 0.2 * sin(_time * 7.0)
		_mat.set_shader_parameter("strength", _glow * pulse)

		var cooling := _cooldown_left > 0.0
		_alpha = move_toward(_alpha, 0.45 if _see_through else 1.0, delta * 6.0)
		var tint := Color(0.7, 0.7, 0.75) if cooling else Color.WHITE
		tint.a = _alpha
		_sprite.modulate = tint
		if cooling:
			_prompt.text = "%s (%d giây)" % [device_name, ceili(_cooldown_left)]
			_prompt.modulate = Color(1.0, 0.55, 0.55, _glow)
		else:
			_prompt.text = "[E] " + device_name
			_prompt.modulate = Color(1.0, 1.0, 1.0, _glow)


	func interact(player: Node) -> void:
		if _cooldown_left > 0.0:
			_feedback(false, "Chưa dùng được")
			return

		var hp = player.get("hp")
		var max_hp = player.get("max_hp")
		var food = player.get("food")
		var max_food = player.get("max_food")
		var need_hp: bool = hp != null and max_hp != null and hp < max_hp
		var need_food: bool = food != null and max_food != null and food < max_food

		var give_hp := heal_amount
		var give_food := food_amount
		var text := message if message != "" else device_name

		# Thiết bị cấp HP / FOOD chỉ dùng được khi nhân vật đang cần
		var has_items := not items.is_empty()
		var is_supply := heal_amount > 0.0 or food_amount > 0.0 or has_items
		var useful := not is_supply
		if is_supply:
			var gives_food := food_amount > 0.0 or has_items
			if (heal_amount > 0.0 and need_hp) or (gives_food and need_food):
				useful = true
		if not useful:
			_feedback(false, not_needed_text)
			return

		if has_items:
			var it: Dictionary = _next_item()
			give_food = it.get("food", 0.0)
			give_hp = it.get("hp", 0.0)
			text = "%s  +%d FOOD" % [it.get("name", "?"), int(give_food)]
			if give_hp > 0.0:
				text += "  +%d HP" % int(give_hp)

		if give_hp > 0.0 and player.has_method("heal"):
			player.heal(give_hp)
		if give_food > 0.0 and player.has_method("eat"):
			player.eat(give_food)

		_cooldown_left = cooldown
		used.emit(self, player)
		_feedback(true, text)


	# Lấy lần lượt từng vật phẩm theo thứ tự xáo trộn (hết vòng thì xáo lại)
	func _next_item() -> Dictionary:
		if _bag.is_empty():
			_bag = items.duplicate()
			_bag.shuffle()
		return _bag.pop_back()


	# ok = true: nháy xanh. ok = false: nháy đỏ + rung.
	func _feedback(ok: bool, text: String) -> void:
		var col := Color(0.3, 1.0, 0.4) if ok else Color(1.0, 0.3, 0.3)
		_mat.set_shader_parameter("flash_color", col)
		if _flash_tween != null:
			_flash_tween.kill()
		_flash_tween = create_tween()
		_flash_tween.tween_method(
			func(v: float) -> void: _mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.4)

		if not ok:
			if _shake_tween != null:
				_shake_tween.kill()
			_sprite.position = _base_pos
			_shake_tween = create_tween()
			for i in 3:
				_shake_tween.tween_property(_sprite, "position:x", _base_pos.x + 6.0, 0.04)
				_shake_tween.tween_property(_sprite, "position:x", _base_pos.x - 6.0, 0.04)
			_shake_tween.tween_property(_sprite, "position:x", _base_pos.x, 0.04)

		var l := _make_label(text, col, rect.position.y - 64.0)
		l.z_index = 60
		add_child(l)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(l, "position:y", l.position.y - 40.0, 1.0)
		tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.6)
		tw.chain().tween_callback(l.queue_free)


	func _make_label(text: String, col: Color, y: float) -> Label:
		var l := Label.new()
		l.text = text
		l.size = Vector2(300.0, 28.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", col)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 8)
		var x := clampf(rect.get_center().x - 150.0, _bounds.position.x + 4.0, _bounds.end.x - 304.0)
		l.position = Vector2(x, y)
		l.z_index = 50
		return l
