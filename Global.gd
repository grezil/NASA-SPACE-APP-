extends Node
## Global autoload holding player save data.

const SAVE_PATH := "user://save.cfg"

var player_hp: float = 100.0
var player_food: float = 100.0
var player_position: Vector2 = Vector2.ZERO
var current_scene: String = "res://game.tscn"

func save_game() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("player", "hp", player_hp)
	cfg.set_value("player", "food", player_food)
	cfg.set_value("player", "pos_x", player_position.x)
	cfg.set_value("player", "pos_y", player_position.y)
	cfg.set_value("game", "scene", current_scene)
	var err = cfg.save(SAVE_PATH)
	if err != OK:
		push_error("Save failed: %s" % err)
	else:
		print("Game saved.")

func load_game() -> bool:
	var cfg = ConfigFile.new()
	var err = cfg.load(SAVE_PATH)
	if err != OK:
		return false
	player_hp = float(cfg.get_value("player", "hp", 100.0))
	player_food = float(cfg.get_value("player", "food", 100.0))
	player_position = Vector2(
		float(cfg.get_value("player", "pos_x", 0.0)),
		float(cfg.get_value("player", "pos_y", 0.0))
	)
	current_scene = String(cfg.get_value("game", "scene", "res://game.tscn"))
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func reset_save() -> void:
	player_hp = 100.0
	player_food = 100.0
	player_position = Vector2.ZERO
	current_scene = "res://game.tscn"
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)