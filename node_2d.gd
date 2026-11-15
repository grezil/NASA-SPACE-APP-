extends Control

# Gọi đúng tên các Node theo cây Scene
@onready var play_btn = $VBoxContainer/Play
@onready var credit_btn = $VBoxContainer/Credit
@onready var save_btn = $VBoxContainer/Save

@onready var title_label = $TitleSprite
@onready var selector = get_node_or_null("Selector")
@onready var fade_overlay = get_node_or_null("FadeOverlay")

@onready var credit_screen = get_node_or_null("CanvasLayer/CreditScreen")
@onready var credits_text = get_node_or_null("CanvasLayer/CreditScreen/CreditsText")

var selector_tween: Tween
var is_rolling_credits: bool = false
var credit_speed: float = 65.0 # Tốc độ chữ chạy (pixel/giây)

func _ready():
	# Ẩn màn hình Credit lúc mới mở game
	if credit_screen:
		credit_screen.visible = false

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

	# 4. Nhạc nền menu (tự tạo AudioStreamPlayer nếu scene chưa có)
	_ensure_bgm()

func _process(delta):
	if is_rolling_credits and credits_text and credit_screen:
		# Chữ trượt từ trên xuống dưới
		credits_text.position.y += credit_speed * delta
		
		# Tự động tắt khi dòng cuối cùng trôi qua hết đáy màn hình
		if credits_text.position.y > credit_screen.size.y:
			close_credits()

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

const MUSIC_PATH := "res://Jimmy Fontanez - Dub Hub ♫ NO COPYRIGHT 8-bit Music.mp3"

var bgm: AudioStreamPlayer

## Menu music: reuse a BGM/AudioStreamPlayer node in the scene, or create one.
func _ensure_bgm() -> AudioStreamPlayer:
	if bgm != null and is_instance_valid(bgm):
		return bgm
	bgm = get_node_or_null("BGM") as AudioStreamPlayer
	if bgm == null:
		bgm = find_child("BGM", true, false) as AudioStreamPlayer
	if bgm == null:
		bgm = get_node_or_null("CanvasLayer/BGM") as AudioStreamPlayer
	if bgm == null:
		bgm = AudioStreamPlayer.new()
		bgm.name = "BGM"
		if ResourceLoader.exists(MUSIC_PATH):
			bgm.stream = load(MUSIC_PATH) as AudioStream
		bgm.volume_db = -8.0
		add_child(bgm)
	if bgm.stream != null and not bgm.playing:
		bgm.play()
	return bgm

func _on_play_pressed():
	var music := _ensure_bgm()
	if music != null and music.playing:
		var music_tween := create_tween()
		music_tween.tween_property(music, "volume_db", -40.0, 1.0)
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
	if not credit_screen or not credits_text: return
	
	hide_selector()
	credits_text.position.y = -1000.0
	credit_screen.visible = true
	
	# Chờ 1 frame để lấy đúng chiều cao khối chữ và tránh nhận nhầm cú click mở nút
	await get_tree().process_frame
	credits_text.position.y = -credits_text.size.y
	is_rolling_credits = true

func _input(event):
	if is_rolling_credits:
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			close_credits()

func close_credits():
	is_rolling_credits = false
	if credit_screen:
		credit_screen.visible = false
