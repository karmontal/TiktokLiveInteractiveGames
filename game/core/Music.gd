extends Node
## Background music. Games call Music.play("<name>") for assets/music/<name>.ogg
## (made by tools/make_music.py); the track loops until another one is played.
## User args: --no-music, --music-volume=<dB> (default -10).

const DIR := "res://assets/music/"

var _player := AudioStreamPlayer.new()
var _current := ""
var _enabled := true


func _ready() -> void:
	_player.volume_db = -10.0
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-music":
			_enabled = false
		elif arg.begins_with("--music-volume="):
			_player.volume_db = float(arg.trim_prefix("--music-volume="))
	add_child(_player)


func play(track: String) -> void:
	if not _enabled or track == _current:
		return
	var path := DIR + track + ".ogg"
	var stream: AudioStreamOggVorbis = null
	if ResourceLoader.exists(path):
		stream = load(path)
	if stream == null and FileAccess.file_exists(path):
		# Not imported yet (new file, project never reopened in the editor): read the .ogg itself.
		stream = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	if stream == null:
		push_warning("music not found: " + path)
		return
	stream.loop = true
	_current = track
	_player.stream = stream
	_player.play()


func stop() -> void:
	_current = ""
	_player.stop()
