extends Node2D
## Quiz screens (720x1280): question/reveal, stream leaderboard, and the break between rounds.
## Rules live in QuizLogic.gd; this file only draws. User arg --pack=<name> picks
## games/quiz/packs/<name>.json (default "general"; a football pack can sit next to it).

const QuizLogic := preload("res://games/quiz/QuizLogic.gd")
const Ui := preload("res://core/Ui.gd")

const PACK_DIR := "res://games/quiz/packs/"
const DEFAULT_PACK := "general"
const W := 720.0
const RIGHT := HORIZONTAL_ALIGNMENT_RIGHT
const LEFT := HORIZONTAL_ALIGNMENT_LEFT
const OPTION_Y := 414.0
const OPTION_H := 92.0
const OPTION_GAP := 14.0
const BAR_W := 576.0
const GIFT_ROWS := [
	["1+", "هدية صغيرة", "1–9 كوين · مثل الوردة", "+3 ثواني للسؤال ونقاطك ×2", Color("#7cc4ff")],
	["10+", "هدية متوسطة", "10–99 كوين", "حذف جواب غلط للكل ونقاطك ×2", Color("#c084fc")],
	["100+", "هدية كبيرة", "100 كوين وفوق", "تجميد الوقت 10 ثواني ونقاطك ×3 واسمك على الشاشة", Color("#ffd23f")],
]

var logic := QuizLogic.new()
var title := "تحدّي المعلومات"
var music := "quiz_think"
# Colors; a pack can override them with "theme": {"bg", "card", "panel", "bar", "accent"}
var _bg := Ui.BG
var _card := Ui.CARD
var _panel := Ui.PANEL
var _bar := Ui.BAR
var _accent := Ui.ACCENT

var _ui: Control
var _play: Control
var _board: Control
var _break: Control
var _avatars: Array[Panel] = []
var _users := {}                     # uid -> user, for avatars that load later

# play screen
var _counter: Label
var _category: Label
var _timer_box: Control
var _timer_fill: ColorRect
var _timer_num: Label
var _question: Label
var _rows: Array[Panel] = []
var _bars: Array[ColorRect] = []
var _letters: Array[Label] = []
var _texts: Array[Label] = []
var _pcts: Array[Label] = []
var _answered: Label
var _notice: Label
var _notice_left := 0.0
var _live: Control
var _likes_count: Label
var _likes_fill: ColorRect
var _top_cards: Array[Dictionary] = []
var _reveal: Control
var _fast_rows: Array[Dictionary] = []
var _bottom_title: Label
var _chips: Control

# board screen
var _podium: Array[Dictionary] = []
var _board_rows: Array[Dictionary] = []
var _board_sub: Label
var _board_clock: Label

# break screen
var _break_clock: Label
var _cat_box: HBoxContainer
var _champ_avatar: Panel
var _champ_name: Label
var _champ_score: Label
var _champ_title: Label

var _popup: Panel                    # big-gift banner over the header, never over the question
var _popup_text: Label
var _popup_tween: Tween
var _status: Label


func _ready() -> void:
	_load_pack()
	Music.play(music)
	_ui = Ui.root(self)
	Ui.rect(_ui, _bg, Vector2.ZERO, Vector2(W, Ui.H))
	_build_play()
	_build_board()
	_build_break()
	_build_overlay()
	EventBus.event_received.connect(_on_event)
	EventBus.connection_changed.connect(_on_connection)
	AvatarCache.avatar_ready.connect(_on_avatar)
	_on_connection(EventBus.connected)
	_apply(logic.start())


func _process(delta: float) -> void:
	_apply(logic.tick(delta))
	_refresh(delta)


func _load_pack() -> void:
	var pack := DEFAULT_PACK
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pack="):
			pack = arg.trim_prefix("--pack=")
	var data = JSON.parse_string(FileAccess.get_file_as_string(PACK_DIR + pack + ".json"))
	if not (data is Dictionary):
		push_error("quiz pack '%s' not found or not valid JSON" % pack)
		data = {"questions": []}
	title = str(data.get("title", title))
	music = str(data.get("music", music))
	var theme: Dictionary = data.get("theme", {})
	_bg = Color(theme.get("bg", _bg.to_html()))
	_card = Color(theme.get("card", _card.to_html()))
	_panel = Color(theme.get("panel", _panel.to_html()))
	_bar = Color(theme.get("bar", _bar.to_html()))
	_accent = Color(theme.get("accent", _accent.to_html()))
	logic.load_questions(data.get("questions", []))


# ---------------------------------------------------------------- events

func _on_event(ev: Dictionary) -> void:
	_apply(logic.handle(ev))


func _apply(effects: Array[Dictionary]) -> void:
	for fx in effects:
		match fx["kind"]:
			"intermission":
				_show_break(fx)
			"question":
				_show_question(fx)
			"reveal":
				_show_reveal(fx)
			"board":
				_show_board(fx)
			"removed":
				var by: Dictionary = fx["by"]
				_say("انحذف جواب غلط بفضل اللايكات" if by.is_empty() else "%s حذف جواب غلط للكل" % _name(by))
			"joker":
				_say("%s عمل فولو: بيقدر يغيّر جوابه مرة" % _name(fx["user"]))
			"multiplier":
				if fx["source"] == "share":
					_say("%s عمل شير: نقاطه ×2" % _name(fx["user"]))
			"gift":
				_on_gift(fx)


func _on_gift(fx: Dictionary) -> void:
	var name := _name(fx["user"])
	var gift: String = fx["gift"].get("name", "هدية")
	match fx["tier"]:
		"large":
			_show_popup("%s\n%s ×%d · تجميد الوقت ونقاطه ×3" % [name, gift, fx["count"]])
		"medium":
			_say("%s بعت %s: نقاطه ×2" % [name, gift])
		_:
			var extra := " +%d ثواني" % int(fx["seconds"]) if fx["seconds"] > 0 else ""
			_say("%s بعت %s:%s نقاطه ×2" % [name, gift, extra])


func _on_connection(connected: bool) -> void:
	_status.text = "● متصل" if connected else "● غير متصل"
	_status.add_theme_color_override("font_color", Ui.GOOD if connected else Color("#ff5c5c"))


func _on_avatar(user_id: String, texture: Texture2D) -> void:
	for holder in _avatars:
		if holder.get_meta("uid", "") == user_id:
			Ui.set_avatar(holder, _users.get(user_id, {}), texture)


func _set_avatar(holder: Panel, user: Dictionary) -> void:
	var uid := str(user.get("id", ""))
	_users[uid] = user
	Ui.set_avatar(holder, user, AvatarCache.get_avatar(uid, str(user.get("avatar", ""))))


# ---------------------------------------------------------------- phases

func _show_only(screen: Control) -> void:
	for s in [_play, _board, _break]:
		s.visible = s == screen


func _show_break(fx: Dictionary) -> void:
	_show_only(_break)
	for c in _cat_box.get_children():
		_cat_box.remove_child(c)
		c.queue_free()
	for cat in fx["categories"]:
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = _panel
		sb.border_color = _accent
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(24)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		chip.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = str(cat)
		l.add_theme_font_size_override("font_size", 26)
		l.add_theme_font_override("font", Ui.font(700))
		chip.add_child(l)
		_cat_box.add_child(chip)
	var champ: Dictionary = fx["champion"]
	var has := not champ.is_empty()
	_champ_title.text = "بطل الجولة الماضية" if has else "أول جولة بالبث"
	_champ_name.text = _name(champ["user"]) if has else "مين رح يكون البطل؟"
	_champ_score.text = ("%s\nنقطة" % Ui.number(champ["score"])) if has else ""
	_champ_avatar.visible = has
	if has:
		_set_avatar(_champ_avatar, champ["user"])


func _show_question(fx: Dictionary) -> void:
	_show_only(_play)
	_counter.text = "سؤال %d من %d" % [fx["index"] + 1, fx["total"]]
	_category.text = fx["category"]
	_question.text = fx["text"]
	for i in 4:
		_texts[i].text = fx["options"][i]
		Ui.restyle(_rows[i], _panel)
		_rows[i].modulate = Color.WHITE
		_letters[i].add_theme_color_override("font_color", _accent)
	_timer_box.visible = true
	_live.visible = true
	_reveal.visible = false
	_bottom_title.text = "جاوب بالتعليق: A · B · C · D"
	_chips.visible = true
	var top := logic.top(3)
	for i in 3:
		var card: Dictionary = _top_cards[i]
		card["root"].visible = i < top.size()
		if i < top.size():
			card["name"].text = _name(top[i]["user"])
			card["score"].text = Ui.number(top[i]["score"])
			_set_avatar(card["avatar"], top[i]["user"])
	_top_cards[0]["empty"].visible = top.is_empty()


func _show_reveal(fx: Dictionary) -> void:
	var answer: int = fx["answer"]
	for i in 4:
		if i == answer:
			Ui.restyle(_rows[i], Ui.GOOD_BG, Ui.GOOD, 3)
			_letters[i].add_theme_color_override("font_color", Ui.GOOD)
			_rows[i].modulate = Color.WHITE
		else:
			_rows[i].modulate = Color(1, 1, 1, 0.4)
	_timer_box.visible = false
	_live.visible = false
	_reveal.visible = true
	_chips.visible = false
	_answered.text = "جاوب صح %d من %d" % [fx["right"], fx["answered"]]
	var fastest: Array = fx["fastest"]
	for i in 3:
		var row: Dictionary = _fast_rows[i]
		row["root"].visible = i < fastest.size()
		if i < fastest.size():
			var w: Dictionary = fastest[i]
			row["name"].text = _name(w["user"])
			row["time"].text = "%.1f ث%s" % [w["time"], "  ·  ×%d" % w["multiplier"] if w["multiplier"] > 1 else ""]
			row["points"].text = "+%d" % w["points"]
			_set_avatar(row["avatar"], w["user"])
	_fast_rows[0]["empty"].visible = fastest.is_empty()


func _show_board(fx: Dictionary) -> void:
	_show_only(_board)
	var top: Array = fx["top"]
	_board_sub.text = "من أول البث لهلأ" if not top.is_empty() else "لسا ما حدا جاوب صح، الجولة الجاية إلك!"
	for i in 3:
		var p: Dictionary = _podium[i]
		p["root"].visible = i < top.size()
		if i < top.size():
			p["name"].text = _name(top[i]["user"])
			p["score"].text = Ui.number(top[i]["score"])
			_set_avatar(p["avatar"], top[i]["user"])
	for i in _board_rows.size():
		var r: Dictionary = _board_rows[i]
		var k := i + 3
		r["root"].visible = k < top.size()
		if k < top.size():
			r["name"].text = _name(top[k]["user"])
			r["correct"].text = "%d صح" % top[k]["correct"]
			r["score"].text = Ui.number(top[k]["score"])
			_set_avatar(r["avatar"], top[k]["user"])


func _refresh(delta: float) -> void:
	var secs := maxi(0, ceili(logic.time_left))
	match logic.phase:
		"question":
			var frac := clampf(logic.time_left / logic.phase_length, 0.0, 1.0)
			_timer_fill.size.x = BAR_W * frac
			_timer_fill.position.x = 112.0 + BAR_W * (1.0 - frac)
			_timer_num.text = str(secs)
			var total := maxi(1, logic.answered_count())
			for i in 4:
				var removed := i in logic.removed
				var pct := float(logic.counts[i]) / total
				_bars[i].size.x = 656.0 * pct
				_bars[i].position.x = 656.0 * (1.0 - pct)
				_pcts[i].text = "" if removed else "%d%%" % roundi(pct * 100.0)
				_rows[i].modulate = Color(1, 1, 1, 0.3) if removed else Color.WHITE
			_answered.text = "جاوب %d مشارك" % logic.answered_count()
			if logic.removed.size() >= logic.max_removed:
				_likes_count.text = "ما ضل غير جوابين"
				_likes_fill.size.x = 616.0
			else:
				_likes_count.text = "%d / %d" % [logic.likes_bucket, logic.likes_per_removal]
				_likes_fill.size.x = 616.0 * logic.likes_bucket / logic.likes_per_removal
		"reveal":
			_bottom_title.text = "السؤال الجاي بعد %d ثواني" % secs if logic.question_index + 1 < logic.round_questions.size() \
					else "ترتيب البث بعد %d ثواني" % secs
		"board":
			_board_clock.text = "الجولة الجاية بعد 0:%02d · جاوب بالتعليق A · B · C · D" % (secs + int(logic.intermission_s))
		"intermission":
			_break_clock.text = "%d:%02d" % [secs / 60, secs % 60]
	if _notice_left > 0.0:
		_notice_left -= delta
		_notice.modulate.a = clampf(_notice_left, 0.0, 1.0)


# ---------------------------------------------------------------- notices

func _say(text: String) -> void:
	_notice.text = text
	_notice_left = 3.5
	_notice.modulate.a = 1.0


func _show_popup(text: String) -> void:
	_popup_text.text = text
	_popup.visible = true
	_popup.scale = Vector2(0.4, 0.4)
	_popup.modulate.a = 1.0
	if _popup_tween:
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.tween_property(_popup, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tween.tween_interval(2.6)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.4)
	_popup_tween.tween_callback(func(): _popup.visible = false)


func _name(user) -> String:
	return str(user.get("name", "?")) if user is Dictionary else "?"


# ---------------------------------------------------------------- building

func _avatar(parent: Node, pos: Vector2, diameter: float, ring: Color, ring_width := 4) -> Panel:
	var a := Ui.avatar(parent, pos, diameter, ring, ring_width)
	_avatars.append(a)
	return a


func _pill(parent: Node, text: String, pos: Vector2, width: float) -> Label:
	Ui.panel(parent, _panel, pos, Vector2(width, 42), 21)
	return Ui.label(parent, text, 20, pos, width, Color.WHITE, 600, HORIZONTAL_ALIGNMENT_CENTER, 42)


func _build_play() -> void:
	_play = Ui.layer(_ui)
	Ui.label(_play, title, 34, Vector2(380, 26), 308, _accent, 800, RIGHT, 50)
	_category = _pill(_play, "", Vector2(32, 30), 160)
	_counter = _pill(_play, "", Vector2(202, 30), 170)

	_timer_box = Ui.layer(_play)
	Ui.panel(_timer_box, _panel, Vector2(112, 117), Vector2(BAR_W, 14), 7)
	_timer_fill = Ui.rect(_timer_box, _accent, Vector2(112, 117), Vector2(BAR_W, 14))
	Ui.panel(_timer_box, _bg, Vector2(32, 92), Vector2(64, 64), 32, _accent, 4)
	_timer_num = Ui.label(_timer_box, "", 30, Vector2(32, 92), 64, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_CENTER, 64)

	Ui.panel(_play, _card, Vector2(32, 180), Vector2(656, 214), 28)
	_question = Ui.paragraph(_play, "", 42, Vector2(56, 186), Vector2(608, 202), Color.WHITE, 800)

	for i in 4:
		var y := OPTION_Y + i * (OPTION_H + OPTION_GAP)
		var row := Ui.panel(_play, _panel, Vector2(32, y), Vector2(656, OPTION_H), 20)
		row.clip_contents = true
		_bars.append(Ui.rect(row, Color(0.23, 0.51, 0.96, 0.38), Vector2(656, 0), Vector2(0, OPTION_H)))
		Ui.panel(row, _bg, Vector2(578, 14), Vector2(64, 64), 16)
		_letters.append(Ui.label(row, QuizLogic.LETTERS[i], 34, Vector2(578, 14), 64, _accent, 800,
				HORIZONTAL_ALIGNMENT_CENTER, 64))
		_texts.append(Ui.label(row, "", 31, Vector2(110, 0), 450, Color.WHITE, 700, RIGHT, OPTION_H))
		_pcts.append(Ui.label(row, "", 26, Vector2(18, 0), 90, Color(1, 1, 1, 0.85), 800, LEFT, OPTION_H))
		_rows.append(row)

	_answered = Ui.label(_play, "", 22, Vector2(400, 836), 288, Ui.MUTED, 600, RIGHT, 40)
	_notice = Ui.label(_play, "", 22, Vector2(32, 836), 400, _accent, 700, LEFT, 40)

	_live = Ui.layer(_play)
	Ui.panel(_live, _card, Vector2(32, 884), Vector2(656, 86), 20)
	Ui.label(_live, "لايكات لحذف جواب غلط", 22, Vector2(300, 890), 368, Color.WHITE, 600, RIGHT, 38)
	_likes_count = Ui.label(_live, "", 22, Vector2(52, 890), 260, Ui.LIKE, 800, LEFT, 38)
	_likes_count.text_direction = Control.TEXT_DIRECTION_AUTO   # "17 / 50", not "50 / 17"
	Ui.panel(_live, _bg, Vector2(52, 938), Vector2(616, 12), 6)
	_likes_fill = Ui.rect(_live, Ui.LIKE, Vector2(52, 938), Vector2(0, 12))
	Ui.label(_live, "متصدرين البث", 22, Vector2(32, 978), 656, Color(1, 1, 1, 0.85), 800, RIGHT, 36)
	for i in 3:
		var x := 32.0 + (2 - i) * 222.0        # first place on the right
		var card := Ui.panel(_live, _card, Vector2(x, 1018), Vector2(212, 70), 18)
		var av := _avatar(card, Vector2(152, 13), 44, Ui.MEDALS[i], 3)
		var nm := Ui.label(card, "", 19, Vector2(10, 6), 136, Color.WHITE, 600, RIGHT, 30)
		var sc := Ui.label(card, "", 17, Vector2(10, 34), 136, _accent, 800, RIGHT, 28)
		_top_cards.append({"root": card, "avatar": av, "name": nm, "score": sc})
	_top_cards[0]["empty"] = Ui.label(_live, "جاوب صح وكون أول واحد هون!", 22, Vector2(32, 1018), 656, Ui.MUTED, 600,
			HORIZONTAL_ALIGNMENT_CENTER, 70)

	_reveal = Ui.layer(_play)
	Ui.panel(_reveal, _card, Vector2(32, 884), Vector2(656, 206), 24)
	Ui.label(_reveal, "الأسرع", 26, Vector2(32, 888), 656, _accent, 800, HORIZONTAL_ALIGNMENT_CENTER, 40)
	for i in 3:
		var y := 932.0 + i * 52.0
		var row := Ui.panel(_reveal, _panel, Vector2(48, y), Vector2(624, 46), 14)
		Ui.panel(row, Ui.MEDALS[i], Vector2(584, 7), Vector2(32, 32), 16)
		Ui.label(row, str(i + 1), 18, Vector2(584, 7), 32, _bg, 800, HORIZONTAL_ALIGNMENT_CENTER, 32)
		var av := _avatar(row, Vector2(540, 5), 36, Ui.AVATAR_BG, 0)
		var nm := Ui.label(row, "", 22, Vector2(300, 0), 230, Color.WHITE, 700, RIGHT, 46)
		var tm := Ui.label(row, "", 17, Vector2(110, 0), 180, Ui.MUTED, 500, RIGHT, 46)
		var pts := Ui.label(row, "", 24, Vector2(12, 0), 96, Ui.GOOD, 800, LEFT, 46)
		_fast_rows.append({"root": row, "avatar": av, "name": nm, "time": tm, "points": pts})
	_fast_rows[0]["empty"] = Ui.label(_reveal, "ما حدا جاوب صح هالمرة", 24, Vector2(32, 930), 656, Ui.MUTED, 600,
			HORIZONTAL_ALIGNMENT_CENTER, 150)

	Ui.rect(_play, _bar, Vector2(0, 1100), Vector2(W, 180))
	_bottom_title = Ui.label(_play, "", 26, Vector2(0, 1106), W, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_CENTER, 46)
	_chips = Ui.layer(_play)
	var chip_text := ["50 لايك = حذف جواب غلط", "فولو = تغيير جوابك مرة", "شير = نقاطك ×2",
			"هدية = وقت إضافي ونقاط ×2 أو ×3"]
	for i in 4:
		var pos := Vector2(364.0 if i % 2 == 0 else 32.0, 1160.0 + (i / 2) * 54.0)
		Ui.panel(_chips, _card, pos, Vector2(324, 46), 12)
		Ui.label(_chips, chip_text[i], 19, pos, 324, Color.WHITE, 500, HORIZONTAL_ALIGNMENT_CENTER, 46)


func _build_board() -> void:
	_board = Ui.layer(_ui)
	Ui.label(_board, "ترتيب البث", 56, Vector2(0, 30), W, _accent, 800, HORIZONTAL_ALIGNMENT_CENTER, 80)
	_board_sub = Ui.label(_board, "", 23, Vector2(0, 108), W, Ui.MUTED, 500, HORIZONTAL_ALIGNMENT_CENTER, 40)
	var heights := [150.0, 110.0, 80.0]
	var xs := [255.0, 485.0, 25.0]           # 1st in the middle, 2nd right, 3rd left
	for i in 3:
		var col := Ui.layer(_board)
		var x: float = xs[i]
		var base_top: float = 560.0 - heights[i]
		var d := 120.0 if i == 0 else 100.0
		var av := _avatar(col, Vector2(x + (210 - d) / 2, base_top - d - 84), d, Ui.MEDALS[i], 5)
		var nm := Ui.label(col, "", 24, Vector2(x, base_top - 80), 210, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_CENTER, 40)
		var sc := Ui.label(col, "", 22, Vector2(x, base_top - 42), 210, Ui.MEDALS[i], 800, HORIZONTAL_ALIGNMENT_CENTER, 36)
		Ui.panel(col, Ui.MEDALS[i], Vector2(x, base_top), Vector2(210, heights[i] + 18), 18)
		Ui.label(col, str(i + 1), 46, Vector2(x, base_top), 210, _bg, 800, HORIZONTAL_ALIGNMENT_CENTER, heights[i])
		_podium.append({"root": col, "avatar": av, "name": nm, "score": sc})
	Ui.rect(_board, _bg, Vector2(0, 560), Vector2(W, 20))
	for i in 7:
		var y := 588.0 + i * 74.0
		var row := Ui.panel(_board, _card, Vector2(32, y), Vector2(656, 64), 16)
		Ui.label(row, str(i + 4), 24, Vector2(600, 0), 40, Color(1, 1, 1, 0.7), 800, HORIZONTAL_ALIGNMENT_CENTER, 64)
		var av := _avatar(row, Vector2(546, 9), 46, Ui.AVATAR_BG, 0)
		var nm := Ui.label(row, "", 24, Vector2(250, 0), 284, Color.WHITE, 600, RIGHT, 64)
		var cr := Ui.label(row, "", 18, Vector2(130, 0), 110, Ui.MUTED, 500, HORIZONTAL_ALIGNMENT_CENTER, 64)
		var sc := Ui.label(row, "", 24, Vector2(16, 0), 110, _accent, 800, LEFT, 64)
		_board_rows.append({"root": row, "avatar": av, "name": nm, "correct": cr, "score": sc})
	Ui.rect(_board, _bar, Vector2(0, 1150), Vector2(W, 130))
	Ui.label(_board, "مش بالقائمة؟ كل جواب صح بيقرّبك", 24, Vector2(0, 1162), W, Color.WHITE, 800,
			HORIZONTAL_ALIGNMENT_CENTER, 44)
	_board_clock = Ui.label(_board, "", 19, Vector2(0, 1208), W, Ui.MUTED, 500, HORIZONTAL_ALIGNMENT_CENTER, 40)


func _build_break() -> void:
	_break = Ui.layer(_ui)
	Ui.label(_break, title, 44, Vector2(210, 34), 478, _accent, 800, RIGHT, 64)
	Ui.label(_break, "الجولة الجاية بتبلّش بعد", 22, Vector2(210, 100), 478, Ui.MUTED, 500, RIGHT, 40)
	Ui.panel(_break, _bg, Vector2(32, 28), Vector2(150, 150), 75, _accent, 6)
	_break_clock = Ui.label(_break, "", 52, Vector2(32, 28), 150, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_CENTER, 150)

	Ui.label(_break, "تصنيفات الجولة الجاية", 22, Vector2(32, 196), 656, Color(1, 1, 1, 0.85), 800, RIGHT, 38)
	_cat_box = HBoxContainer.new()
	_cat_box.position = Vector2(32, 240)
	_cat_box.size = Vector2(656, 52)
	_cat_box.layout_direction = Control.LAYOUT_DIRECTION_RTL
	_cat_box.add_theme_constant_override("separation", 10)
	_break.add_child(_cat_box)

	Ui.panel(_break, Color("#2a2210"), Vector2(32, 314), Vector2(656, 104), 24, _accent, 3)
	_champ_avatar = _avatar(_break, Vector2(592, 328), 76, _accent, 4)
	_champ_title = Ui.label(_break, "", 19, Vector2(200, 324), 380, _accent, 700, RIGHT, 32)
	_champ_name = Ui.label(_break, "", 30, Vector2(200, 352), 380, Color.WHITE, 800, RIGHT, 52)
	_champ_score = Ui.paragraph(_break, "", 20, Vector2(48, 326), Vector2(140, 80), Color.WHITE, 800)

	Ui.panel(_break, _card, Vector2(32, 436), Vector2(656, 96), 22)
	Ui.paragraph(_break, "اكتب بالتعليق A أو B أو C أو D · أول جواب بس بيحسب\nكل ما جاوبت صح أسرع نقاطك بتزيد", 22,
			Vector2(48, 440), Vector2(624, 88))

	Ui.label(_break, "مجاناً", 22, Vector2(32, 546), 656, Color(1, 1, 1, 0.85), 800, RIGHT, 38)
	var free := [["50 لايك", "حذف جواب غلط للكل", Ui.LIKE], ["فولو", "تغيير جوابك مرة", Ui.BLUE],
			["شير", "نقاطك ×2", Ui.GOOD]]
	for i in 3:
		var x := 32.0 + (2 - i) * 222.0
		Ui.panel(_break, _card, Vector2(x, 588), Vector2(212, 92), 18)
		Ui.label(_break, free[i][0], 23, Vector2(x, 594), 212, free[i][2], 800, HORIZONTAL_ALIGNMENT_CENTER, 40)
		Ui.label(_break, free[i][1], 18, Vector2(x, 632), 212, Color(1, 1, 1, 0.85), 500, HORIZONTAL_ALIGNMENT_CENTER, 36)

	Ui.label(_break, "الهدايا", 22, Vector2(32, 694), 656, Color(1, 1, 1, 0.85), 800, RIGHT, 38)
	for i in GIFT_ROWS.size():
		var g: Array = GIFT_ROWS[i]
		var y := 736.0 + i * 104.0
		var row := Ui.panel(_break, _card, Vector2(32, y), Vector2(656, 94), 20)
		Ui.rect(row, g[4], Vector2(650, 14), Vector2(6, 66))
		Ui.panel(row, _bg, Vector2(566, 15), Vector2(64, 64), 16)
		Ui.label(row, g[0], 22, Vector2(566, 15), 64, g[4], 800, HORIZONTAL_ALIGNMENT_CENTER, 64)
		Ui.label(row, "%s  ·  %s" % [g[1], g[2]], 21, Vector2(16, 8), 536, g[4], 800, RIGHT, 38)
		Ui.label(row, g[3], 20, Vector2(16, 46), 536, Color.WHITE, 600, RIGHT, 38)

	Ui.rect(_break, _bar, Vector2(0, 1196), Vector2(W, 84))
	Ui.label(_break, "الترتيب بيبلّش من الصفر مع كل بث", 20, Vector2(0, 1196), W, Color(1, 1, 1, 0.8), 500,
			HORIZONTAL_ALIGNMENT_CENTER, 84)


func _build_overlay() -> void:
	_popup = Ui.panel(_ui, Color("#3b1d4a"), Vector2(24, 14), Vector2(672, 158), 26, _accent, 4)
	_popup.pivot_offset = Vector2(336, 79)
	_popup_text = Ui.paragraph(_popup, "", 34, Vector2(16, 6), Vector2(640, 146), _accent, 800)
	_popup.visible = false
	_status = Ui.label(_ui, "", 15, Vector2(8, 0), 120, Color.WHITE, 500, LEFT, 24)
