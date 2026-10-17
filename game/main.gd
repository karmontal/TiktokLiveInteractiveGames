extends Node
## Picks the game to run. User args (after `--`):
##   --game=tug_of_war   which game to load
##   --fps-log           print FPS every 5 s (for the server benchmark)

const GAMES := {
	"tug_of_war": "res://games/tug_of_war/TugOfWar.gd",
}

var _fps_log := false
var _fps_timer := 0.0


func _ready() -> void:
	var game := "tug_of_war"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game="):
			game = arg.trim_prefix("--game=")
		elif arg == "--fps-log":
			_fps_log = true
	if not GAMES.has(game):
		push_warning("unknown game '%s', using tug_of_war" % game)
		game = "tug_of_war"
	add_child(load(GAMES[game]).new())


func _process(delta: float) -> void:
	if not _fps_log:
		return
	_fps_timer += delta
	if _fps_timer >= 5.0:
		_fps_timer = 0.0
		print("fps=%d" % Engine.get_frames_per_second())
