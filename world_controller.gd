extends Node
## Quản lý chuyển đổi giữa nội thất Happy Valley và bề mặt Sao Hỏa.
## WorldController là node con của Game; Room, MarsMap và Player là node cùng cấp.
## Vì NodePath được tính tương đối từ WorldController nên phải dùng ../Room, ../MarsMap, ../Player.

@export_node_path("Node2D") var room_path: NodePath = ^"../Room"
@export_node_path("Node2D") var map_path: NodePath = ^"../MarsMap"
@export_node_path("CharacterBody2D") var player_path: NodePath = ^"../Player"
@export var exterior_spawn := Vector2(-1050.0, 300.0)

var _room: Node2D
var _map: Node2D
var _player: CharacterBody2D
var _inside_surface := false
var _interior_position := Vector2.ZERO
var _surface_position := Vector2.ZERO
var _room_collision_state: Dictionary = {}


func _ready() -> void:
	_resolve_nodes()
	if _room == null or _map == null or _player == null:
		push_error("WorldController: kiểm tra SceneTree. Cần Room, MarsMap và Player là các node con của Game; WorldController cũng là node con của Game.")
		if _map != null:
			_map.visible = false
			_map.set_process(false)
			_map.set_process_unhandled_input(false)
		return

	# Khởi động trong căn cứ: map ẩn hoàn toàn, Room hoạt động.
	_room.visible = true
	_room.process_mode = Node.PROCESS_MODE_INHERIT
	_room.set_process(true)
	_room.set_process_unhandled_input(true)
	_set_room_collisions_enabled(true)

	_map.visible = false
	if _map.has_method("set_active"):
		_map.call("set_active", false)
	else:
		_map.set_process(false)
		_map.set_process_unhandled_input(false)


func _resolve_nodes() -> void:
	# Các NodePath mặc định ../... là đường dẫn đúng từ WorldController lên Game.
	_room = get_node_or_null(room_path) as Node2D
	_map = get_node_or_null(map_path) as Node2D
	_player = get_node_or_null(player_path) as CharacterBody2D

	# Fallback nếu người dùng đặt các node trong một nhánh con của Game.
	var scene_root := get_parent()
	if scene_root != null:
		if _room == null:
			_room = scene_root.find_child("Room", true, false) as Node2D
		if _map == null:
			_map = scene_root.find_child("MarsMap", true, false) as Node2D
		if _player == null:
			_player = scene_root.find_child("Player", true, false) as CharacterBody2D


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		get_viewport().set_input_as_handled()
		if _inside_surface:
			return_to_interior()
		else:
			enter_exterior()


## F6: đi từ nội thất ra bề mặt để kiểm thử.
func enter_exterior() -> void:
	if _inside_surface or _room == null or _map == null or _player == null:
		return

	_interior_position = _player.global_position
	_player.velocity = Vector2.ZERO

	# Ẩn cả Room (bao gồm sprites/thiết bị) nhưng giữ node sống để SolSystem không mất.
	_room.visible = false
	_room.set_process(false)
	_room.set_process_unhandled_input(false)
	_set_room_collisions_enabled(false)

	# Chỉ hiển thị và kích hoạt map ngoài.
	_map.visible = true
	if _map.has_method("set_active"):
		_map.call("set_active", true)
	else:
		_map.set_process(true)
		_map.set_process_unhandled_input(true)

	var destination := exterior_spawn
	if _surface_position != Vector2.ZERO:
		destination = _map.to_local(_surface_position)
	_player.global_position = _map.to_global(destination)
	_inside_surface = true
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		camera.reset_smoothing()


## Gọi từ Airlock ngoài bản đồ hoặc nhấn F6 để quay về.
func return_to_interior() -> void:
	if not _inside_surface or _room == null or _map == null or _player == null:
		return

	_surface_position = _player.global_position
	_player.velocity = Vector2.ZERO

	# Tắt map trước để collision và prompt ngoài bề mặt không còn hoạt động.
	if _map.has_method("set_active"):
		_map.call("set_active", false)
	else:
		_map.set_process(false)
		_map.set_process_unhandled_input(false)
	_map.visible = false

	# Hiện lại toàn bộ căn cứ và bật collision ban đầu.
	_room.visible = true
	_room.set_process(true)
	_room.set_process_unhandled_input(true)
	_set_room_collisions_enabled(true)
	_player.global_position = _interior_position
	_inside_surface = false
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		camera.reset_smoothing()

	if _room.has_method("_limit_camera"):
		_room.call_deferred("_limit_camera")


func is_on_surface() -> bool:
	return _inside_surface


func _set_room_collisions_enabled(enabled: bool) -> void:
	if _room == null:
		return
	var stack: Array[Node] = [_room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject2D:
			var key := int(node.get_instance_id())
			if not _room_collision_state.has(key):
				_room_collision_state[key] = {
					"layer": node.collision_layer,
					"mask": node.collision_mask,
				}
			var saved: Dictionary = _room_collision_state[key]
			if enabled:
				node.collision_layer = int(saved["layer"])
				node.collision_mask = int(saved["mask"])
			else:
				node.collision_layer = 0
				node.collision_mask = 0
		for child in node.get_children():
			stack.append(child)
