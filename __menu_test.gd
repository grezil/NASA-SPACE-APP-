extends Node

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _key(code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(4)
	var u := InputEventKey.new()
	u.keycode = code
	u.physical_keycode = code
	u.pressed = false
	Input.parse_input_event(u)
	await _frames(6)

func _ready() -> void:
	var game: Node = load("res://game.tscn").instantiate()
	add_child(game)
	await _frames(20)
	await _key(KEY_ESCAPE)
	var room: Node = game.get_node("Room")
	var sol: Node = null
	for c in room.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.has_method("get_global_name") and sc.get_global_name() == "SolSystem":
			sol = c
	print("TEST: sol=", sol != null, " paused=", get_tree().paused)

	# menu máy tính: mở bằng handler thật, rồi bấm 1..5 cho từng mục
	for i in [1, 2, 3, 4, 5]:
		sol.call("_on_computer_used", null, null)
		await _frames(8)
		var opened_kind = sol.get("_panel_kind")
		await _key(KEY_1 + (i - 1))
		await _frames(12)
		print("TEST: mục %d (menu %s) -> kind=%s open=%s paused=%s" % [
			i, opened_kind, sol.get("_panel_kind"), str(sol.get("_panel_open")), str(get_tree().paused)])
		await _key(KEY_ESCAPE)
		await _key(KEY_ESCAPE)
		await _frames(6)

	# hội thoại thiết bị
	sol.call("_on_food_used", null, null)
	await _frames(8)
	print("TEST: food -> kind=%s open=%s" % [sol.get("_panel_kind"), str(sol.get("_panel_open"))])
	await _key(KEY_ESCAPE)
	sol.call("_on_fuel_used", null, null)
	await _frames(8)
	print("TEST: fuel -> kind=%s open=%s" % [sol.get("_panel_kind"), str(sol.get("_panel_open"))])
	await _key(KEY_ESCAPE)

	# cây trồng + pin + NASA qua handler trực tiếp
	sol.call("_start_mars_research")
	await _frames(10)
	print("TEST: research -> kind=%s mg=%s" % [sol.get("_panel_kind"), str(sol.get("_mg_active"))])
	await _key(KEY_SPACE)
	await _frames(10)
	print("TEST: DONE paused=", get_tree().paused)
	get_tree().quit(0)
