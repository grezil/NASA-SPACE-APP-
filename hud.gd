extends Node
## HUD tự tìm Player (qua group "player") và 2 thanh HP / FOOD (ProgressBar).
## Gắn vào node HUD (CanvasLayer hoặc Control đều được). Không cần gán gì trong Inspector.

var hp_bar: Range
var food_bar: Range


func _ready() -> void:
	await get_tree().process_frame   # đợi Player khởi tạo xong

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("HUD: không tìm thấy Player (cần gắn player.gd)")
		return

	_find_bars()
	player.hp_changed.connect(_on_hp_changed)
	player.food_changed.connect(_on_food_changed)
	player.died.connect(_on_player_died)
	_on_hp_changed(player.hp, player.max_hp)


func _find_bars() -> void:
	var bars := find_children("*", "Range", true, false)
	for b in bars:
		var n := String(b.name).to_lower()
		if hp_bar == null and ("hp" in n or "health" in n):
			hp_bar = b
		elif food_bar == null and ("food" in n or "hunger" in n):
			food_bar = b
	# Không khớp tên thì lấy theo thứ tự: thanh đầu = HP, thanh hai = FOOD
	if hp_bar == null and bars.size() > 0:
		hp_bar = bars[0]
	if food_bar == null and bars.size() > 1:
		food_bar = bars[1]


func _on_hp_changed(value: float, max_value: float) -> void:
	if hp_bar == null:
		return
	hp_bar.max_value = max_value
	create_tween().tween_property(hp_bar, "value", value, 0.15)


func _on_food_changed(value: float, max_value: float) -> void:
	if food_bar == null:
		return
	food_bar.max_value = max_value
	food_bar.value = value


func _on_player_died() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "GAME OVER"
	label.add_theme_font_size_override("font_size", 48)
	label.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(label)
	add_child(layer)
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()
