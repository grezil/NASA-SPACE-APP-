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
	print("Mở thông tin Credits")
