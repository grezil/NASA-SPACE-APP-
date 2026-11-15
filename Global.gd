extends Node
## Global game state + save/load (autoload).
##
## Holds the player vitals, ship resources, inventory and the greenhouse beds.
## Beds are stored as plain dictionaries so they serialize directly to the
## save file and can advance while the game is closed (offline growth).

const SAVE_PATH := "user://save.cfg"
const SAVE_VERSION := 2

const MAX_OXYGEN := 100.0
const MAX_WATER := 100.0
const MAX_POWER := 100.0
const MAX_FUEL := 100.0

# --- Player vitals -----------------------------------------------------------
var player_hp: float = 100.0
var player_food: float = 100.0
var player_position: Vector2 = Vector2.ZERO
var current_scene: String = "res://game.tscn"

# --- Ship resources ----------------------------------------------------------
var oxygen: float = 100.0
var water: float = 100.0
var power: float = 100.0
var fuel: float = 0.0
var credits: int = 100

# --- Inventory: item_id -> count --------------------------------------------
var inventory: Dictionary = {}

# --- Greenhouse beds ---------------------------------------------------------
# { plant, progress, water, dry_time, withered, planted_at }
var beds: Array = []

# --- Runtime (not saved) -----------------------------------------------------
var session_loaded: bool = false
var ui_open: bool = false
var saved_at: int = 0
var oxygen_machine_on: bool = true

func _ready() -> void:
	if not session_loaded:
		if has_save():
			load_game()
		else:
			new_game()
		session_loaded = true

# --- New game ----------------------------------------------------------------
func new_game() -> void:
	player_hp = 100.0
	player_food = 100.0
	player_position = Vector2.ZERO
	oxygen = MAX_OXYGEN
	water = 60.0
	power = 100.0
	fuel = 0.0
	credits = 100
	inventory = {
		"seed_potato": 2,
		"seed_cherry_tomato": 3,
		"seed_basil": 2,
	}
	beds = []
	for i in 6:
		beds.append(_empty_bed())
	saved_at = int(Time.get_unix_time_from_system())

func _empty_bed() -> Dictionary:
	return {"plant": "", "progress": 0.0, "water": 0.0, "dry_time": 0.0,
		"withered": false, "planted_at": 0}

# --- Inventory helpers -------------------------------------------------------
func add_item(item_id: String, amount: int = 1) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + amount
	if inventory[item_id] <= 0:
		inventory.erase(item_id)

func count_item(item_id: String) -> int:
	return int(inventory.get(item_id, 0))

func take_item(item_id: String, amount: int = 1) -> bool:
	if count_item(item_id) < amount:
		return false
	inventory[item_id] = count_item(item_id) - amount
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	return true

func add_credits(amount: int) -> void:
	credits = max(0, credits + amount)

# --- Beds --------------------------------------------------------------------
func bed(index: int) -> Dictionary:
	if index < 0 or index >= beds.size():
		return {}
	return beds[index]

func plant(bed_index: int, plant_id: String) -> bool:
	if bed_index < 0 or bed_index >= beds.size():
		return false
	var b: Dictionary = beds[bed_index]
	if str(b["plant"]) != "":
		return false
	if not take_item(GameData.seed_id(plant_id), 1):
		return false
	b["plant"] = plant_id
	b["progress"] = 0.0
	b["water"] = 100.0
	b["dry_time"] = 0.0
	b["withered"] = false
	b["planted_at"] = int(Time.get_unix_time_from_system())
	beds[bed_index] = b
	return true

func harvest(bed_index: int) -> Dictionary:
	## Returns {"plant": id, "count": n} or {} if nothing to harvest.
	if bed_index < 0 or bed_index >= beds.size():
		return {}
	var b: Dictionary = beds[bed_index]
	var plant_id := str(b["plant"])
	if plant_id == "" or bool(b["withered"]):
		return {}
	var data := GameData.plant(plant_id)
	if b["progress"] < float(data.get("grow_time", 120.0)):
		return {}
	var amount := int(data.get("yield", 1))
	add_item(GameData.crop_id(plant_id), amount)
	beds[bed_index] = _empty_bed()
	return {"plant": plant_id, "count": amount}

# --- Tick --------------------------------------------------------------------
## Advances every bed. Returns oxygen produced this tick by mature plants.
func tick_beds(delta: float) -> float:
	var oxygen_out := 0.0
	for i in beds.size():
		var b: Dictionary = beds[i]
		var plant_id := str(b["plant"])
		if plant_id == "":
			continue
		var data := GameData.plant(plant_id)
		var grow_time := float(data.get("grow_time", 120.0))
		var water_level := float(b["water"])
		var ratio := float(b["progress"]) / maxf(grow_time, 0.001)

		if bool(b["withered"]):
			continue

		# Water drains slowly; without water the plant stops growing.
		if water_level > 0.0:
			var drain := 100.0 / maxf(float(data.get("grow_time", 120.0)) * 1.35, 1.0)
			b["water"] = maxf(0.0, water_level - drain * delta)
			b["progress"] = minf(grow_time, float(b["progress"]) + delta)
			b["dry_time"] = 0.0
		else:
			b["dry_time"] = float(b["dry_time"]) + delta
			if float(b["dry_time"]) > 45.0 and ratio < 0.999:
				b["withered"] = true

		if float(b["progress"]) >= grow_time:
			oxygen_out += float(data.get("oxygen", 0.0))
		beds[i] = b
	return oxygen_out

func water_bed(bed_index: int) -> bool:
	if bed_index < 0 or bed_index >= beds.size():
		return false
	var b: Dictionary = beds[bed_index]
	if str(b["plant"]) == "":
		return false
	if water < 6.0:
		return false
	water -= 6.0
	b["water"] = 100.0
	b["dry_time"] = 0.0
	beds[bed_index] = b
	return true

# --- Offline growth ----------------------------------------------------------
func apply_offline(elapsed: float) -> void:
	if elapsed <= 0.0:
		return
	# Water evaporates; dry beds stop growing. Cap the simulated window so a
	# months-old save does not instantly fill the greenhouse.
	elapsed = min(elapsed, 60.0 * 60.0)
	var simulated := 0.0
	var step := 1.0
	while simulated < elapsed:
		tick_beds(step)
		simulated += step

# --- Save / load -------------------------------------------------------------
func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("meta", "saved_at", int(Time.get_unix_time_from_system()))

	cfg.set_value("player", "hp", player_hp)
	cfg.set_value("player", "food", player_food)
	cfg.set_value("player", "pos_x", player_position.x)
	cfg.set_value("player", "pos_y", player_position.y)
	cfg.set_value("game", "scene", current_scene)

	cfg.set_value("ship", "oxygen", oxygen)
	cfg.set_value("ship", "water", water)
	cfg.set_value("ship", "power", power)
	cfg.set_value("ship", "fuel", fuel)
	cfg.set_value("ship", "credits", credits)
	cfg.set_value("ship", "oxygen_machine_on", oxygen_machine_on)

	cfg.set_value("inventory", "items", inventory)
	cfg.set_value("beds", "list", beds)

	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("Save failed: %s" % err)
	else:
		print("Game saved.")

func load_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	var version := int(cfg.get_value("meta", "version", 1))
	if version < SAVE_VERSION:
		# Old (v1) saves only had hp/food/position - start the farm fresh.
		player_hp = float(cfg.get_value("player", "hp", 100.0))
		player_food = float(cfg.get_value("player", "food", 100.0))
		player_position = Vector2(
			float(cfg.get_value("player", "pos_x", 0.0)),
			float(cfg.get_value("player", "pos_y", 0.0)))
		new_game()
		return true

	player_hp = float(cfg.get_value("player", "hp", 100.0))
	player_food = float(cfg.get_value("player", "food", 100.0))
	player_position = Vector2(
		float(cfg.get_value("player", "pos_x", 0.0)),
		float(cfg.get_value("player", "pos_y", 0.0)))
	current_scene = String(cfg.get_value("game", "scene", "res://game.tscn"))

	oxygen = float(cfg.get_value("ship", "oxygen", MAX_OXYGEN))
	water = float(cfg.get_value("ship", "water", MAX_WATER))
	power = float(cfg.get_value("ship", "power", MAX_POWER))
	fuel = float(cfg.get_value("ship", "fuel", 0.0))
	credits = int(cfg.get_value("ship", "credits", 100))
	oxygen_machine_on = bool(cfg.get_value("ship", "oxygen_machine_on", true))

	inventory = cfg.get_value("inventory", "items", {})
	beds = cfg.get_value("beds", "list", [])
	while beds.size() < 6:
		beds.append(_empty_bed())

	saved_at = int(cfg.get_value("meta", "saved_at", 0))
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func reset_save() -> void:
	new_game()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

## Seconds since the last save (for offline growth).
func seconds_since_save() -> float:
	if saved_at <= 0:
		return 0.0
	return max(0.0, Time.get_unix_time_from_system() - saved_at)
