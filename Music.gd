extends Node
## Global background music (autoload "Music").
##
## Lives outside the scenes, so the track keeps playing when Menu.tscn hands
## over to game.tscn (and survives reload_current_scene on death).

const TRACK_PATH := "res://Jimmy Fontanez - Dub Hub ♫ NO COPYRIGHT 8-bit Music.mp3"
const MENU_VOLUME_DB := -8.0
const GAME_VOLUME_DB := -14.0
const SILENT_DB := -60.0

var player: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	add_child(player)

	if not ResourceLoader.exists(TRACK_PATH):
		push_warning("Music: không tìm thấy file nhạc " + TRACK_PATH)
		return
	var stream := load(TRACK_PATH) as AudioStream
	if stream == null:
		push_warning("Music: không load được " + TRACK_PATH)
		return
	# Loop even if the .import file says otherwise.
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

	player.stream = stream
	player.volume_db = SILENT_DB
	player.play()
	fade_to(MENU_VOLUME_DB, 0.8)
	print("Music: đang phát '%s' (%.1fs, loop)" % [TRACK_PATH.get_file(), stream.get_length()])


func fade_to(target_db: float, duration: float) -> void:
	if player == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", target_db, maxf(duration, 0.01))


func menu_music() -> void:
	fade_to(MENU_VOLUME_DB, 0.6)


func game_music() -> void:
	fade_to(GAME_VOLUME_DB, 1.0)


func stop_music() -> void:
	fade_to(SILENT_DB, 0.8)
