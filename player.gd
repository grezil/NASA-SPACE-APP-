extends CharacterBody2D
## Nhân vật top-down cho Happy Valley (Godot 4.x).
## Tự tìm Sprite2D / AnimatedSprite2D và Camera2D.
## Camera2D đặt ngang hàng trong Game.tscn cũng được tự chuyển thành con của Player.

signal hp_changed(value: float, max_value: float)
signal food_changed(value: float, max_value: float)
signal died

@export_group("Movement")
@export var walk_speed := 140.0
## Optional level rectangle (world space); the body is clamped inside it.
@export var room_bounds: Rect2 = Rect2()
@export var run_speed := 230.0
@export var acceleration := 1200.0
@export var friction := 1400.0

@export_group("Survival")
@export var max_hp := 100.0
@export var max_food := 100.0
@export var food_drain_per_sec := 0.2
@export var run_food_drain_per_sec := 0.5
@export var starving_damage_per_sec := 2.0
@export var hp_regen_per_sec := 1.0
@export var regen_food_threshold := 50.0

@export_group("Camera")
@export var auto_camera := true
@export var camera_smoothing := true

var hp := 0.0
var food := 0.0
var facing := "down"
var is_dead := false

var sprite: Node2D
var anim: AnimatedSprite2D
var _base_y := 0.0
var _bob_time := 0.0


func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	hp = max_hp
	food = max_food
	_setup_wasd()
	_find_sprite()
	if auto_camera:
		_ensure_camera.call_deferred()
	hp_changed.emit(hp, max_hp)
	food_changed.emit(food, max_food)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var running := Input.is_physical_key_pressed(KEY_SHIFT) and dir != Vector2.ZERO and food > 0.0
	var target_speed := run_speed if running else walk_speed

	if dir != Vector2.ZERO:
		velocity = velocity.move_toward(dir * target_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	_clamp_to_room()
	_update_animation(dir, running, delta)
	_update_survival(delta, running)


func _clamp_to_room() -> void:
	if room_bounds.size.x <= 0.0 or room_bounds.size.y <= 0.0:
		return
	global_position = global_position.clamp(room_bounds.position, room_bounds.end)


# ---------- Tự tìm node ----------

func _find_sprite() -> void:
	for child in find_children("*", "", true, false):
		if child is AnimatedSprite2D:
			sprite = child
			anim = child
			return
	for child in find_children("*", "", true, false):
		if child is Sprite2D:
			sprite = child
			_base_y = sprite.position.y
			return
	push_warning("Player: không tìm thấy Sprite2D / AnimatedSprite2D")


func _ensure_camera() -> void:
	# Ưu tiên camera đang hoạt động; nếu chưa có thì tìm Camera2D trong scene.
	var cam := get_viewport().get_camera_2d()
	if cam == null and get_tree().current_scene != null:
		cam = get_tree().current_scene.find_child("Camera2D", true, false) as Camera2D

	# Chỉ tạo mới khi scene thực sự chưa có camera.
	if cam == null:
		cam = Camera2D.new()
		cam.name = "Camera2D"
		cam.position_smoothing_enabled = camera_smoothing
		add_child(cam)
	else:
		# Camera là sibling của Player trong Game.tscn cũ; chuyển nó vào Player
		# để Camera2D theo đúng vị trí nhân vật khi di chuyển.
		if cam.get_parent() != self:
			cam.reparent(self, false)
		cam.position = Vector2.ZERO
		cam.enabled = true
		if camera_smoothing:
			cam.position_smoothing_enabled = true

	cam.make_current()


# ---------- Animation ----------

func _update_animation(dir: Vector2, running: bool, delta: float) -> void:
	if sprite == null:
		return

	if dir != Vector2.ZERO:
		if absf(dir.x) > absf(dir.y):
			facing = "right" if dir.x > 0.0 else "left"
		else:
			facing = "down" if dir.y > 0.0 else "up"

	if anim != null and anim.sprite_frames != null:
		var state := "walk" if dir != Vector2.ZERO else "idle"
		var full := "%s_%s" % [state, facing]
		anim.speed_scale = 1.6 if running else 1.0
		if anim.sprite_frames.has_animation(full):
			anim.play(full)
		elif anim.sprite_frames.has_animation(state):
			if facing == "left":
				anim.flip_h = true
			elif facing == "right":
				anim.flip_h = false
			anim.play(state)
		return

	# Sprite tĩnh: lật ngang và nhún nhẹ khi di chuyển.
	if sprite is Sprite2D and dir.x != 0.0:
		(sprite as Sprite2D).flip_h = dir.x < 0.0
	if dir != Vector2.ZERO:
		_bob_time += delta * (16.0 if running else 11.0)
		sprite.position.y = _base_y + sin(_bob_time) * 1.5
	else:
		sprite.position.y = lerpf(sprite.position.y, _base_y, 0.3)


# ---------- Sinh tồn ----------

func _update_survival(delta: float, running: bool) -> void:
	var drain := run_food_drain_per_sec if running else food_drain_per_sec
	food = maxf(food - drain * delta, 0.0)
	food_changed.emit(food, max_food)

	if food <= 0.0:
		take_damage(starving_damage_per_sec * delta, false)
	elif food >= regen_food_threshold and hp < max_hp:
		hp = minf(hp + hp_regen_per_sec * delta, max_hp)
		hp_changed.emit(hp, max_hp)


func take_damage(amount: float, flash := true) -> void:
	if is_dead:
		return
	hp = maxf(hp - amount, 0.0)
	hp_changed.emit(hp, max_hp)
	if flash and sprite != null:
		sprite.modulate = Color(1, 0.3, 0.3)
		create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)
	if hp <= 0.0:
		_die()


func heal(amount: float) -> void:
	if is_dead:
		return
	hp = minf(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)


func eat(amount: float) -> void:
	food = minf(food + amount, max_food)
	food_changed.emit(food, max_food)


func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation("die"):
		anim.play("die")
	elif sprite != null:
		create_tween().tween_property(sprite, "modulate:a", 0.0, 0.6)
	died.emit()


func _setup_wasd() -> void:
	var actions := {"ui_left": KEY_A, "ui_right": KEY_D, "ui_up": KEY_W, "ui_down": KEY_S}
	for action in actions:
		var ev := InputEventKey.new()
		ev.physical_keycode = actions[action]
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)
