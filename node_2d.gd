extends Control

# Gọi đúng tên các Node theo cây Scene
@onready var play_btn = $VBoxContainer/Play
@onready var credit_btn = $VBoxContainer/Credit
@onready var save_btn = $VBoxContainer/Save

@onready var title_label = $TitleSprite
@onready var selector = get_node_or_null("Selector")
@onready var fade_overlay = get_node_or_null("FadeOverlay")

var selector_tween: Tween

func _ready():
	# 1. Kết nối sự kiện Click nút
	if play_btn: play_btn.pressed.connect(_on_play_pressed)
	if save_btn: save_btn.pressed.connect(_on_save_pressed)
	if credit_btn: credit_btn.pressed.connect(_on_credits_pressed)
	
	# 2. Đăng ký hiệu ứng Rê chuột & Click cho các nút
	var buttons = [play_btn, credit_btn, save_btn]
	for btn in buttons:
		if btn:
			btn.pivot_offset = btn.size / 2
			btn.mouse_entered.connect(_on_button_hover.bind(btn, true))
			btn.mouse_exited.connect(_on_button_hover.bind(btn, false))
			btn.button_down.connect(_on_button_click.bind(btn, true))
			btn.button_up.connect(_on_button_click.bind(btn, false))
		
	# 3. Khởi chạy hiệu ứng nhấp nhô tiêu đề
	start_title_floating()

	# 4. Nhạc nền do autoload Music lo (phát xuyên scene)
	Music.play_menu()

# --- HIỆU ỨNG TIÊU ĐỀ LƠ LỬNG ---
func start_title_floating():
	if not title_label: return
	var base_y = title_label.position.y
	var tween = create_tween().set_loops()
	tween.tween_property(title_label, "position:y", base_y - 8, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(title_label, "position:y", base_y + 8, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# --- HIỆU ỨNG RÊ CHUỘT (HOVER) ---
func _on_button_hover(btn: Button, is_hovered: bool):
	var tween = create_tween().set_parallel(true)
	if is_hovered:
		# Phóng to nhẹ + đổi màu chữ cam retro
		tween.tween_property(btn, "scale", Vector2(1.15, 1.15), 0.1)
		tween.tween_property(btn, "modulate", Color(1, 0.6, 0.2), 0.1)
		move_selector_to_button(btn)
	else:
		# Trả về trạng thái ban đầu
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1)
		tween.tween_property(btn, "modulate", Color(1, 1, 1), 0.1)
		hide_selector()

# --- DI CHUYỂN CON TRỎ SELECTOR ---
func move_selector_to_button(btn: Button):
	if not selector: return
	
	selector.visible = true
	var btn_pos = btn.global_position
	var target_x = btn_pos.x - 35
	var target_y = btn_pos.y + (btn.size.y / 2) - (selector.size.y / 2)
	
	selector.global_position = Vector2(target_x, target_y)
	
	if selector_tween and selector_tween.is_running():
		selector_tween.kill()
		
	selector_tween = create_tween().set_loops()
	selector_tween.tween_property(selector, "global_position:x", target_x - 5, 0.25)
	selector_tween.tween_property(selector, "global_position:x", target_x, 0.25)

func hide_selector():
	if not selector: return
	selector.visible = false
	if selector_tween and selector_tween.is_running():
		selector_tween.kill()

# --- HIỆU ỨNG CLICK NÚT ---
func _on_button_click(btn: Button, is_down: bool):
	var tween = create_tween()
	if is_down:
		tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.05)
	else:
		tween.tween_property(btn, "scale", Vector2(1.15, 1.15), 0.05)

# --- CHỨC NĂNG CÁC NÚT BẤM ---
@onready var anim_player = $CanvasLayer/AnimationPlayer

func _on_play_pressed():
	# Sang nhạc ingame (crossfade), nhạc menu tắt dần.
	Music.play_game()
	print("Đang chạy Cutscene chuyển cảnh...")
	
	if anim_player:
		# Chạy animation fade_out làm tối màn hình
		anim_player.play("fade_out")
		# Đợi animation chạy xong hoàn toàn
		await anim_player.animation_finished
	
	# Chuyển sang màn chơi chính
	get_tree().change_scene_to_file("res://game.tscn")

func _on_save_pressed():
	Global.player_hp = 100.0
	Global.player_food = 100.0
	Global.player_position = Vector2.ZERO
	Global.current_scene = "res://game.tscn"
	Global.save_game()
	print("Game saved.")

func _on_credits_pressed():
	_build_credits()

# --- CREDITS: cuộn dọc kiểu credit phim --------------------------------------
const CREDITS_SPEED := 58.0      # pixel/giây (dương = chữ trôi từ dưới lên)
const CREDITS_START_GAP := 40.0  # khoảng trống trước dòng đầu

var _credits_layer: CanvasLayer
var _credits_roll: VBoxContainer
var _credits_speed := CREDITS_SPEED
var _credits_opened_ms := 0


func _build_credits() -> void:
	if _credits_layer != null:
		return
	var vp := get_viewport_rect().size

	_credits_layer = CanvasLayer.new()
	_credits_layer.name = "CreditsLayer"
	_credits_layer.layer = 30
	add_child(_credits_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.01, 0.02, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits_layer.add_child(bg)

	# Viền đen trên/dưới cho giống màn ảnh rộng.
	for bar_y in [0.0, vp.y * 0.9]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.position = Vector2(0.0, bar_y)
		bar.size = Vector2(vp.x, vp.y * 0.1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_credits_layer.add_child(bar)

	_credits_roll = VBoxContainer.new()
	_credits_roll.name = "Roll"
	_credits_roll.add_theme_constant_override("separation", 8)
	_credits_roll.position = Vector2(0.0, vp.y + CREDITS_START_GAP)
	_credits_roll.custom_minimum_size = Vector2(vp.x, 0.0)
	_credits_layer.add_child(_credits_roll)

	_credit_line("JUNIOR ASTRONAUT", 38, Color(1.0, 0.78, 0.25))
	_credit_line("MISSION TRAINER", 38, Color(1.0, 0.78, 0.25))
	_credit_gap(26)
	_credit_line("— CREDITS —", 20, Color(0.7, 0.82, 0.95))
	_credit_gap(54)

	_credit_head("MADE BY")
	_credit_name("5joblesS")
	_credit_gap(34)

	_credit_head("GAME DESIGN & CODE")
	_credit_name("grezil (Nhat Nguyenn)")
	_credit_name("KDSpaceTech — bản fork: gameplay Sao Hỏa, nhà kính, UI")
	_credit_gap(34)

	_credit_head("ÂM NHẠC")
	_credit_name("Menu: \"Dub Hub\" — Jimmy Fontanez (No Copyright 8-bit Music)")
	_credit_name("Trong game: \"8-Bit Fantasy & Adventure Music\"")
	_credit_gap(34)

	_credit_head("ĐỒ HOẠ")
	_credit_name("Cây trồng & thiết bị: bộ asset NasaspaceApp — Nguyen Khang Sinh")
	_credit_name("Bề mặt Sao Hỏa: Mars_surface · Radio · SolarPanel · Searching Machine")
	_credit_name("Giao diện, hiệu ứng CRT: 5joblesS")
	_credit_gap(34)

	_credit_head("CÔNG CỤ")
	_credit_name("Godot Engine 4.7.2 — MIT License")
	_credit_name("Silkscreen — Jason Kottke (SIL Open Font License 1.1)")
	_credit_small("Jolt Physics · D3D12 Forward+")
	_credit_gap(34)

	_credit_head("CẢM HỨNG")
	_credit_name("NASA Space Apps Challenge")
	_credit_small("Căn cứ Happy Valley trên Sao Hỏa")
	_credit_gap(34)

	_credit_head("ĐIỀU KHIỂN NHANH")
	_credit_small("WASD / mũi tên: di chuyển      Shift: chạy")
	_credit_small("E: tương tác      TAB: túi đồ      Q: chế độ tiết kiệm")
	_credit_small("1-5: chọn mục      Space: mini-game      Esc: đóng bảng")
	_credit_small("G: module trồng cây      F6: ra/vào Sao Hỏa      T: tua x8")
	_credit_gap(44)

	_credit_line("CẢM ƠN BẠN ĐÃ CHƠI!", 24, Color(1.0, 0.9, 0.5))
	_credit_small("github.com/grezil/NASA-SPACE-APP-")
	_credit_gap(120)

	var hint := Label.new()
	hint.text = "[Esc] hoặc bấm chuột để đóng"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -320.0
	hint.offset_right = 320.0
	hint.offset_top = -32.0
	hint.offset_bottom = -8.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", load("res://Silkscreen-Bold.ttf"))
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_credits_layer.add_child(hint)

	_credits_opened_ms = Time.get_ticks_msec()
	set_process(true)


func _credit_line(text: String, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", load("res://Silkscreen-Bold.ttf"))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	_credits_roll.add_child(label)


func _credit_head(text: String) -> void:
	_credit_gap(10)
	_credit_line(text, 19, Color(0.45, 0.9, 1.0))


func _credit_name(text: String) -> void:
	_credit_line(text, 15, Color(0.95, 0.96, 1.0))


func _credit_small(text: String) -> void:
	_credit_line(text, 12, Color(0.72, 0.78, 0.86))


func _credit_gap(px: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, float(px))
	_credits_roll.add_child(spacer)


func _process(delta: float) -> void:
	if _credits_layer == null or _credits_roll == null:
		return
	_credits_roll.position.y -= _credits_speed * delta
	var vp_h := get_viewport_rect().size.y
	if _credits_roll.position.y + _credits_roll.get_combined_minimum_size().y < 0.0:
		_credits_roll.position.y = vp_h + CREDITS_START_GAP


func _close_credits() -> void:
	if _credits_layer == null:
		return
	_credits_layer.queue_free()
	_credits_layer = null
	_credits_roll = null
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if _credits_layer == null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_credits()
	elif event is InputEventMouseButton and event.pressed:
		# Bỏ qua cú click đầu tiên (chính là cú bấm nút CREDIT) để credit không tắt ngay.
		if Time.get_ticks_msec() - _credits_opened_ms < 400:
			return
		get_viewport().set_input_as_handled()
		_close_credits()
