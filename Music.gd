extends Node
## Global background music (autoload "Music").
##
## Hai track riêng:
##  - menu_theme  : "Dub Hub" — Jimmy Fontanez  (chỉ ở menu bắt đầu game)
##  - ingame_theme: "8-Bit Fantasy & Adventure Music" (trong lúc chơi)
##
## Node này sống ngoài scene nên nhạc không bị cắt khi Menu.tscn -> game.tscn;
## chuyển track bằng crossfade.

const MENU_TRACK := "res://Jimmy Fontanez - Dub Hub ♫ NO COPYRIGHT 8-bit Music.mp3"
const GAME_TRACK := "res://audio/ingame_theme.mp3"

const MENU_VOLUME_DB := -8.0
const GAME_VOLUME_DB := -12.0
const SILENT_DB := -60.0
const FADE_MENU := 0.8
const FADE_GAME := 1.4

var menu_player: AudioStreamPlayer
var game_player: AudioStreamPlayer

var _menu_tween: Tween
var _game_tween: Tween
var _current := ""   # "menu" | "game" | ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_player = _make_player("MenuPlayer", MENU_TRACK)
	game_player = _make_player("GamePlayer", GAME_TRACK)

	# Nếu chạy thẳng scene game (F6) thì vào nhạc ingame luôn, ngược lại là menu.
	await get_tree().process_frame
	var path := ""
	if get_tree().current_scene != null:
		path = get_tree().current_scene.scene_file_path
	if path.ends_with("game.tscn") or path.ends_with("greenhouse.tscn"):
		play_game()
	else:
		play_menu()


func _make_player(node_name: String, path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	add_child(p)
	if not ResourceLoader.exists(path):
		push_warning("Music: không tìm thấy file nhạc %s" % path)
		return p
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Music: không load được %s" % path)
		return p
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	p.stream = stream
	p.volume_db = SILENT_DB
	return p


func play_menu() -> void:
	crossfade("menu")


func play_game() -> void:
	crossfade("game")


func stop_music() -> void:
	_current = ""
	_fade(menu_player, SILENT_DB, 0.8, true)
	_fade(game_player, SILENT_DB, 0.8, true)


func crossfade(target: String) -> void:
	if target == _current:
		return
	_current = target
	if target == "menu":
		_fade(game_player, SILENT_DB, FADE_MENU, true)
		_fade(menu_player, MENU_VOLUME_DB, FADE_GAME, false)
	else:
		_fade(menu_player, SILENT_DB, FADE_GAME, true)
		_fade(game_player, GAME_VOLUME_DB, FADE_GAME, false)
	print("Music: chuyển sang nhạc %s" % ("menu" if target == "menu" else "trong game"))


func _fade(player: AudioStreamPlayer, target_db: float, duration: float, stop_when_done: bool) -> void:
	if player == null or player.stream == null:
		return
	if player == menu_player:
		if _menu_tween != null and _menu_tween.is_valid():
			_menu_tween.kill()
		_menu_tween = create_tween()
		_menu_tween.tween_property(player, "volume_db", target_db, maxf(duration, 0.01))
		if stop_when_done:
			_menu_tween.tween_callback(player.stop)
	else:
		if _game_tween != null and _game_tween.is_valid():
			_game_tween.kill()
		_game_tween = create_tween()
		_game_tween.tween_property(player, "volume_db", target_db, maxf(duration, 0.01))
		if stop_when_done:
			_game_tween.tween_callback(player.stop)
	if target_db > SILENT_DB and not player.playing:
		player.volume_db = SILENT_DB
		player.play()


## Tiện cho code cũ/khác muốn đổi âm lượng tạm thời.
func set_game_volume(db: float) -> void:
	if game_player != null and _current == "game":
		game_player.volume_db = db
