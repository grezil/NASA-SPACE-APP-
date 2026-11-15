extends Node2D
## Cửa sang module trồng cây, đặt trong khoang chính (Game.tscn > Room).
## Không cần ảnh riêng: cửa được vẽ bằng code, bấm E khi đứng gần để đi vào.

@export var door_size := Vector2(150.0, 110.0)
@export var label_text := "MODULE TRỒNG CÂY"
@export var trigger_radius := 120.0

var _player: CharacterBody2D
var _highlight := 0.0
var _focused := false


func _ready() -> void:
	z_index = 3
	set_process(true)
	queue_redraw()
	var body := StaticBody2D.new()
	body.name = "Block"
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(door_size.x, 24.0)
	cs.shape = shape
	cs.position = Vector2(0.0, door_size.y * 0.5 - 12.0)
	body.add_child(cs)
	add_child(body)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		if _player == null:
			return
	var near := _player.global_position.distance_to(global_position) <= trigger_radius
	if near != _focused:
		_focused = near
		queue_redraw()
	if near:
		_highlight = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 320.0)
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _focused or _player == null:
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		enter()


func enter() -> void:
	var controller := get_tree().current_scene.find_child("WorldController", true, false)
	if controller != null and controller.has_method("enter_growing"):
		controller.call("enter_growing")


func _draw() -> void:
	var rect := Rect2(Vector2(-door_size.x * 0.5, -door_size.y * 0.5), door_size)
	# Khung cửa.
	draw_rect(rect, Color(0.05, 0.08, 0.10, 0.88), true)
	var edge := Color(0.35, 0.85, 1.0, 0.55 + 0.45 * _highlight)
	draw_rect(rect, edge, false, 3.0)
	# Hai cánh cửa.
	var half := door_size.x * 0.5
	draw_line(Vector2(-half + 8, -door_size.y * 0.5 + 8), Vector2(-6, 0), edge, 2.0)
	draw_line(Vector2(half - 8, -door_size.y * 0.5 + 8), Vector2(6, 0), edge, 2.0)
	# Ánh sáng từ trong.
	draw_rect(Rect2(Vector2(-half + 10, door_size.y * 0.5 - 14), Vector2(door_size.x - 20, 12)),
		Color(0.3, 0.9, 1.0, 0.10 + 0.18 * _highlight), true)
	# Nhãn.
	var font := ThemeDB.fallback_font
	var text := "[E] " + label_text
	draw_string(font, Vector2(-half + 4, -door_size.y * 0.5 - 12), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))
