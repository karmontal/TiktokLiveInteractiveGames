extends Node
## Picks the game to run: user arg --game=<name> (after `--`), else env LIVE_GAME, else tug_of_war.
##   --fps-log           print FPS every 5 s (for the server benchmark)
## In debug builds (running from the editor) Tab switches to the next game.

const GAMES := {
	"tug_of_war": "res://games/tug_of_war/TugOfWar.gd",
	"quiz": "res://games/quiz/QuizGame.gd",
}

var _fps_log := false
var _fps_timer := 0.0
var _game := ""


func _ready() -> void:
	var game := OS.get_environment("LIVE_GAME")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game="):
			game = arg.trim_prefix("--game=")
		elif arg == "--fps-log":
			_fps_log = true
	if not GAMES.has(game):
		if game != "":
			push_warning("unknown game '%s', using tug_of_war" % game)
		game = "tug_of_war"
	_load(game)


func _load(game: String) -> void:
	for child in get_children():
		child.queue_free()
	_game = game
	add_child(load(GAMES[game]).new())


func _unhandled_input(e: InputEvent) -> void:
	if OS.is_debug_build() and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_TAB:
		var names := GAMES.keys()
		_load(names[(names.find(_game) + 1) % names.size()])


func _process(delta: float) -> void:
	if not _fps_log:
		return
	_fps_timer += delta
	if _fps_timer >= 5.0:
		_fps_timer = 0.0
		print("fps=%d" % Engine.get_frames_per_second())
