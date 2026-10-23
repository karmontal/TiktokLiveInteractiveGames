extends Control
## Start screen of the standalone quiz build (export feature "quiz_app", see tools/windows_quiz/).
## Asks for the TikTok account and the question pack, starts LiveBridge from the "bridge" folder
## next to the .exe, then runs the quiz. The bridge stops with the game.
## Choices are remembered in user://launcher.cfg.

const Ui := preload("res://core/Ui.gd")
const QuizGame := preload("res://games/quiz/QuizGame.gd")
const CONFIG := "user://launcher.cfg"
const PACKS := [["general", "معلومات عامة"], ["football", "كورة"]]

var _pid := -1
var _user: LineEdit
var _pack := "general"
var _pack_buttons: Array[Button] = []
var _error: Label


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG)
	_pack = cfg.get_value("quiz", "pack", "general")
	_build(cfg.get_value("quiz", "user", ""))
	_user.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_stop_bridge()


func _exit_tree() -> void:
	_stop_bridge()


func _start(live: bool) -> void:
	var user := _user.text.strip_edges().trim_prefix("@")
	if live and user == "":
		_error.text = "اكتب اسم حسابك على تيك توك"
		return
	var cfg := ConfigFile.new()
	cfg.set_value("quiz", "user", user)
	cfg.set_value("quiz", "pack", _pack)
	cfg.save(CONFIG)
	var problem := _start_bridge("tiktok" if live else "mock", user)
	if problem != "":
		_error.text = problem
		return
	visible = false
	var game := QuizGame.new()
	game.pack = _pack
	get_parent().add_child(game)


## Runs bridge/python/pythonw.exe bridge/run_bridge.py next to the game (pythonw: no console
## window; run_bridge.py writes the output to bridge/logs). Returns an error, or "".
func _start_bridge(source: String, user: String) -> String:
	var dir := OS.get_executable_path().get_base_dir().path_join("bridge")
	var python := dir.path_join("python").path_join("pythonw.exe")
	if not FileAccess.file_exists(python):
		return "ما لقيت مجلد bridge جنب اللعبة. فك الضغط عن الملف كله بنفس المكان"
	OS.set_environment("LIVEBRIDGE_SOURCE", source)          # the bridge inherits these
	OS.set_environment("TIKTOK_USERNAME", user)
	OS.set_environment("LIVEBRIDGE_LOG_DIR", dir.path_join("logs"))
	OS.set_environment("LIVEBRIDGE_BANNED_WORDS", dir.path_join("banned_words.txt"))
	_pid = OS.create_process(python, [dir.path_join("run_bridge.py")], false)
	return "" if _pid > 0 else "ما زبط تشغيل الـ bridge"


func _stop_bridge() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1


func _pick_pack(pack: String) -> void:
	_pack = pack
	for i in PACKS.size():
		_style(_pack_buttons[i], PACKS[i][0] == _pack)


# ---------------------------------------------------------------- building

func _build(user: String) -> void:
	size = Vector2(Ui.W, Ui.H)
	theme = Theme.new()
	theme.default_font = Ui.font(700)
	Ui.rect(self, Ui.BG, Vector2.ZERO, size)
	Ui.label(self, "تحدّي المعلومات", 50, Vector2(0, 28), Ui.W, Ui.ACCENT, 900, HORIZONTAL_ALIGNMENT_CENTER, 76)
	Ui.label(self, "لعبة أسئلة لبث تيك توك المباشر", 22, Vector2(0, 100), Ui.W, Ui.MUTED, 700,
			HORIZONTAL_ALIGNMENT_CENTER, 36)

	Ui.label(self, "اسم حسابك على تيك توك", 22, Vector2(80, 166), 560, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_RIGHT, 36)
	_user = LineEdit.new()
	_user.text = user
	_user.placeholder_text = "username"
	_user.position = Vector2(80, 206)
	_user.size = Vector2(560, 62)
	_user.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_user.add_theme_font_size_override("font_size", 28)
	_user.add_theme_font_override("font", Ui.font(800))
	_user.add_theme_stylebox_override("normal", _box(Ui.CARD, Ui.ACCENT, 2))
	_user.add_theme_stylebox_override("focus", _box(Ui.CARD, Ui.ACCENT, 3))
	_user.text_submitted.connect(func(_t): _start(true))
	add_child(_user)

	Ui.label(self, "الأسئلة", 22, Vector2(80, 286), 560, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_RIGHT, 36)
	for i in PACKS.size():
		var b := _button(PACKS[i][1], Vector2(80 + (1 - i) * 290, 326), Vector2(270, 56), 24)
		var id: String = PACKS[i][0]
		b.pressed.connect(func(): _pick_pack(id))
		_pack_buttons.append(b)
	_pick_pack(_pack)

	var go := _button("ابدأ", Vector2(80, 414), Vector2(560, 72), 34)
	_style(go, true)
	go.pressed.connect(func(): _start(true))
	var demo := _button("تجربة بدون لايف (مشاهدين وهميين)", Vector2(80, 498), Vector2(560, 50), 20)
	demo.pressed.connect(func(): _start(false))

	_error = Ui.label(self, "", 20, Vector2(40, 556), Ui.W - 80, Color("#ff8a8a"), 800, HORIZONTAL_ALIGNMENT_CENTER, 36)
	Ui.paragraph(self, "بـ TikTok LIVE Studio: أضف Window Capture واختار نافذة اللعبة، وحطها بالنص الفوقاني من البث",
			18, Vector2(60, 600), Vector2(600, 90), Ui.MUTED, 700)


func _button(text: String, pos: Vector2, button_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = button_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_font_override("font", Ui.font(900))
	_style(b, false)
	add_child(b)
	return b


func _style(b: Button, on: bool) -> void:
	var bg := Ui.ACCENT if on else Ui.PANEL
	var fg := Ui.BG if on else Color.WHITE
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, _box(bg.lightened(0.08) if state == "hover" else bg, Ui.ACCENT, 2))
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, fg)


func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(18)
	return sb
