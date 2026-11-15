extends CharacterBody2D
## Player: movement, hunger/HP, death dissolve. Works in any scene that has a
## HUD (CanvasLayer) and a Camera2D sibling.

@export var speed: float = 180.0
## Optional level rectangle (world space); the body is clamped inside it.
@export var room_bounds: Rect2 = Rect2()

# --- Food (hunger) & HP ---
@export var max_hp: float = 100.0
@export var max_food: float = 100.0
# Rates tuned so a full bar lasts ~2 minutes (120s).
@export var hunger_drain_rate: float = 0.83
@export var hp_drain_when_hungry: float = 2.0
@export var hungry_threshold: float = 25.0
@export var eat_amount: float = 30.0

var hp: float
var food: float
var _dead: bool = false

var hp_bar: ProgressBar
var food_bar: ProgressBar
var sprite: Sprite2D
var camera: Camera2D

var _death_label: Label
var _death_tween: Tween
var _default_zoom := Vector2.ONE

signal died
signal hp_changed(new_hp: float)
signal food_changed(new_food: float)

func _ready() -> void:
	hp = Global.player_hp
	food = Global.player_food

	sprite = get_node_or_null("Sprite2D")
	var root := get_parent()
	if root:
		var hud := root.get_node_or_null("HUD")
		if hud:
			hp_bar = hud.get_node_or_null("Root/HPBar")
			if hp_bar == null:
				hp_bar = hud.get_node_or_null("HPBar")
			food_bar = hud.get_node_or_null("Root/FoodBar")
			if food_bar == null:
				food_bar = hud.get_node_or_null("FoodBar")
		camera = root.get_node_or_null("Camera2D")
	if camera:
		_default_zoom = camera.zoom

	died.connect(_on_died)
	_update_bars()

func _physics_process(_delta: float) -> void:
	if _dead or Global.ui_open:
		velocity = Vector2.ZERO
		return
	var input_direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_direction * speed
	move_and_slide()
	_clamp_to_room()

	if camera:
		var target := sprite.global_position if sprite else global_position
		camera.global_position = target

func _clamp_to_room() -> void:
	if room_bounds.size.x <= 0.0 or room_bounds.size.y <= 0.0:
		return
	global_position = global_position.clamp(room_bounds.position, room_bounds.end)

func _process(delta: float) -> void:
	if _dead or Global.ui_open:
		return
	delta = minf(delta, 0.25)

	food = max(food - hunger_drain_rate * delta, 0.0)

	if food <= hungry_threshold and hp > 0.0:
		hp = max(hp - hp_drain_when_hungry * delta, 0.0)

	Global.player_hp = hp
	Global.player_food = food

	if sprite:
		if hp > 0.0 and hp < max_hp * 0.3:
			var t := Time.get_ticks_msec() / 1000.0
			sprite.modulate.a = 0.35 + 0.65 * abs(sin(t * 7.0))
			sprite.modulate.r = 1.0
			sprite.modulate.g = 0.3
			sprite.modulate.b = 0.3
		else:
			sprite.modulate = Color(1, 1, 1, 1)

	_update_bars()

	if hp <= 0.0:
		hp = max_hp
		_dead = true
		emit_signal("died")

func eat() -> void:
	food = min(food + eat_amount, max_food)
	_update_bars()
	emit_signal("food_changed", food)

func take_damage(amount: float) -> void:
	if _dead:
		return
	hp = max(hp - amount, 0.0)
	_update_bars()
	emit_signal("hp_changed", hp)

func heal(amount: float) -> void:
	hp = min(hp + amount, max_hp)
	_update_bars()
	emit_signal("hp_changed", hp)

func _update_bars() -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
	if food_bar:
		food_bar.max_value = max_food
		food_bar.value = food
	emit_signal("hp_changed", hp)
	emit_signal("food_changed", food)

func revive() -> void:
	## Undo the death state (called by the greenhouse after a timeout).
	_dead = false
	set_physics_process(true)
	set_process(true)
	hp = max_hp
	food = max_food
	if sprite:
		sprite.visible = true
		sprite.material = null
		sprite.modulate = Color(1, 1, 1, 1)
		sprite.rotation = 0.0
		sprite.scale = Vector2(0.14993763, 0.13387283)
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
		_death_tween = null
	if _death_label and is_instance_valid(_death_label):
		_death_label.queue_free()
		_death_label = null
	if camera:
		camera.zoom = _default_zoom
	_update_bars()

func _on_died() -> void:
	velocity = Vector2.ZERO
	set_physics_process(false)
	Global.player_hp = max_hp
	Global.player_food = food
	Global.player_position = global_position
	Global.save_game()

	if sprite:
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;

uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.15) = 0.06;
uniform vec4 edge_color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform sampler2D noise_tex;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float noise = texture(noise_tex, UV).r;
	float threshold = noise + (1.0 - UV.y) * 0.35;
	float alpha = step(dissolve_amount, threshold);
	float edge = 1.0 - smoothstep(0.0, edge_width, threshold - dissolve_amount);
	vec3 col = tex.rgb;
	if (edge > 0.0 && alpha < 1.0) {
		col = mix(tex.rgb, edge_color.rgb, edge);
	}
	COLOR = vec4(col, tex.a * alpha);
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var fast_noise := FastNoiseLite.new()
		fast_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		fast_noise.frequency = 0.012
		var img := Image.create(128, 128, false, Image.FORMAT_RF)
		for x in range(128):
			for y in range(128):
				var v := fast_noise.get_noise_2d(x, y)
				img.set_pixel(x, y, Color((v + 1.0) * 0.5, 0.0, 0.0, 1.0))
		var noise_tex := ImageTexture.create_from_image(img)
		mat.set_shader_parameter("noise_tex", noise_tex)
		mat.set_shader_parameter("dissolve_amount", 0.0)
		sprite.material = mat

		var dissolve_tween := create_tween()
		dissolve_tween.tween_method(func(val): mat.set_shader_parameter("dissolve_amount", val), 0.0, 1.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		dissolve_tween.tween_callback(func(): sprite.visible = false)

	var label := Label.new()
	label.text = "Y O U   D I E"
	var spawn_pos := sprite.global_position if sprite else global_position
	label.size = Vector2(240, 40)
	label.position = spawn_pos + Vector2(-120, -45)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	var label_parent := get_parent() if get_parent() else self
	label_parent.add_child(label)
	_death_label = label
	_death_tween = create_tween().set_loops()
	_death_tween.tween_property(label, "modulate:a", 0.4, 0.6).set_trans(Tween.TRANS_SINE)
	_death_tween.tween_property(label, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

	if camera:
		var zoom_tween := create_tween()
		zoom_tween.tween_property(camera, "zoom", Vector2(1.6, 1.6), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
