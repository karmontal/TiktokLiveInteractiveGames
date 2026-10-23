extends Node2D
## Quiz screens (720x720, square so TikTok's comments sit under it): question/reveal, stream leaderboard, and the break between rounds.
## Rules live in QuizLogic.gd; this file only draws. User arg --pack=<name> picks
## games/quiz/packs/<name>.json (default "general"; a football pack can sit next to it).

const QuizLogic := preload("res://games/quiz/QuizLogic.gd")
const Ui := preload("res://core/Ui.gd")

const PACK_DIR := "res://games/quiz/packs/"
const DEFAULT_PACK := "general"
const W := 720.0
const RIGHT := HORIZONTAL_ALIGNMENT_RIGHT
const LEFT := HORIZONTAL_ALIGNMENT_LEFT
const OPTION_Y := 330.0
const OPTION_H := 52.0
const OPTION_GAP := 6.0
const BAR_W := 630.0
const GIFT_ROWS := [
	["1+", "هدية صغيرة", "1–9 كوين · مثل الوردة", "+3 ثواني للسؤال ونقاطك ×2", Color("#7cc4ff")],
	["10+", "هدية متوسطة", "10–99 كوين", "حذف جواب غلط للكل ونقاطك ×2", Color("#c084fc")],
	["100+", "هدية كبيرة", "100 كوين وفوق", "تجميد الوقت 10 ثواني ونقاطك ×3 واسمك على الشاشة", Color("#ffd23f")],
]

var logic := QuizLogic.new()
var pack := DEFAULT_PACK          # set before adding to the tree; user arg --pack=<name> wins
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
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		chip.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = str(cat)
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_font_override("font", Ui.font(800))
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
			_timer_fill.position.x = 74.0 + BAR_W * (1.0 - frac)
			_timer_num.text = str(secs)
			var total := maxi(1, logic.answered_count())
			for i in 4:
				var removed := i in logic.removed
				var pct := float(logic.counts[i]) / total
				_bars[i].size.x = 688.0 * pct
				_bars[i].position.x = 688.0 * (1.0 - pct)
				_pcts[i].text = "" if removed else "%d%%" % roundi(pct * 100.0)
				_rows[i].modulate = Color(1, 1, 1, 0.3) if removed else Color.WHITE
			_answered.text = "جاوب %d مشارك" % logic.answered_count()
			if logic.removed.size() >= logic.max_removed:
				_likes_count.text = "ما ضل غير جوابين"
				_likes_fill.size.x = 656.0
			else:
				_likes_count.text = "%d / %d" % [logic.likes_bucket, logic.likes_per_removal]
				_likes_fill.size.x = 656.0 * logic.likes_bucket / logic.likes_per_removal
		"reveal":
			_bottom_title.text = "السؤال الجاي بعد %d ثواني" % secs if logic.question_index + 1 < logic.round_questions.size() \
					else "ترتيب البث بعد %d ثواني" % secs
		"board":
			_board_clock.text = "الجولة الجاية بعد 0:%02d" % (secs + int(logic.intermission_s))
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
	Ui.panel(parent, _panel, pos, Vector2(width, 40), 20)
	return Ui.label(parent, text, 20, pos, width, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_CENTER, 40)


func _build_play() -> void:
	_play = Ui.layer(_ui)
	Ui.label(_play, title, 30, Vector2(380, 0), 324, _accent, 900, RIGHT, 48)
	_category = _pill(_play, "", Vector2(16, 6), 160)
	_counter = _pill(_play, "", Vector2(186, 6), 170)

	# How to play, at the top: TikTok's comments cover the bottom of the stream.
	Ui.rect(_play, _bar, Vector2(0, 50), Vector2(W, 108))
	_bottom_title = Ui.label(_play, "", 24, Vector2(0, 48), W, Color.WHITE, 900, HORIZONTAL_ALIGNMENT_CENTER, 38)
	_chips = Ui.layer(_play)
	var chip_text := ["50 لايك = حذف جواب غلط", "فولو = تغيير جوابك مرة", "شير = نقاطك ضعفين",
			"هدية = وقت إضافي ونقاط أكثر"]
	for i in 4:
		var pos := Vector2(364.0 if i % 2 == 0 else 16.0, 86.0 + (i / 2) * 36.0)
		Ui.panel(_chips, _card, pos, Vector2(340, 33), 10)
		Ui.label(_chips, chip_text[i], 20, pos, 340, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_CENTER, 33)

	_timer_box = Ui.layer(_play)
	Ui.panel(_timer_box, _panel, Vector2(74, 180), Vector2(BAR_W, 12), 6)
	_timer_fill = Ui.rect(_timer_box, _accent, Vector2(74, 180), Vector2(BAR_W, 12))
	Ui.panel(_timer_box, _bg, Vector2(14, 162), Vector2(50, 50), 25, _accent, 3)
	_timer_num = Ui.label(_timer_box, "", 25, Vector2(14, 162), 50, Color.WHITE, 900, HORIZONTAL_ALIGNMENT_CENTER, 50)

	Ui.panel(_play, _card, Vector2(16, 216), Vector2(688, 108), 22)
	_question = Ui.paragraph(_play, "", 30, Vector2(30, 216), Vector2(660, 108), Color.WHITE, 900)
	_question.add_theme_constant_override("line_spacing", -10)

	for i in 4:
		var y := OPTION_Y + i * (OPTION_H + OPTION_GAP)
		var row := Ui.panel(_play, _panel, Vector2(16, y), Vector2(688, OPTION_H), 16)
		row.clip_contents = true
		_bars.append(Ui.rect(row, Color(0.23, 0.51, 0.96, 0.38), Vector2(688, 0), Vector2(0, OPTION_H)))
		Ui.panel(row, _bg, Vector2(638, 5), Vector2(42, 42), 12)
		_letters.append(Ui.label(row, QuizLogic.LETTERS[i], 27, Vector2(638, 5), 42, _accent, 900,
				HORIZONTAL_ALIGNMENT_CENTER, 42))
		_texts.append(Ui.label(row, "", 26, Vector2(86, 0), 542, Color.WHITE, 800, RIGHT, OPTION_H))
		_pcts.append(Ui.label(row, "", 22, Vector2(12, 0), 74, Color(1, 1, 1, 0.9), 900, LEFT, OPTION_H))
		_rows.append(row)

	_answered = Ui.label(_play, "", 20, Vector2(380, 558), 324, Ui.MUTED, 800, RIGHT, 32)
	_notice = Ui.label(_play, "", 20, Vector2(16, 558), 380, _accent, 800, LEFT, 32)

	_live = Ui.layer(_play)
	Ui.panel(_live, _card, Vector2(16, 592), Vector2(688, 58), 16)
	Ui.label(_live, "لايكات لحذف جواب غلط", 20, Vector2(300, 590), 388, Color.WHITE, 800, RIGHT, 34)
	_likes_count = Ui.label(_live, "", 20, Vector2(32, 590), 260, Ui.LIKE, 900, LEFT, 34)
	_likes_count.text_direction = Control.TEXT_DIRECTION_AUTO   # "17 / 50", not "50 / 17"
	Ui.panel(_live, _bg, Vector2(32, 628), Vector2(656, 12), 6)
	_likes_fill = Ui.rect(_live, Ui.LIKE, Vector2(32, 628), Vector2(0, 12))
	for i in 3:
		var x := 16.0 + (2 - i) * 232.0        # first place on the right
		var card := Ui.panel(_live, _card, Vector2(x, 656), Vector2(224, 60), 16)
		var av := _avatar(card, Vector2(176, 10), 40, Ui.MEDALS[i], 3)
		var nm := Ui.label(card, "", 19, Vector2(8, 2), 162, Color.WHITE, 800, RIGHT, 30)
		var sc := Ui.label(card, "", 17, Vector2(8, 30), 162, _accent, 900, RIGHT, 26)
		_top_cards.append({"root": card, "avatar": av, "name": nm, "score": sc})
	_top_cards[0]["empty"] = Ui.label(_live, "جاوب صح وكون أول واحد بمتصدرين البث!", 21, Vector2(16, 656), 688, Ui.MUTED, 800,
			HORIZONTAL_ALIGNMENT_CENTER, 60)

	_reveal = Ui.layer(_play)
	Ui.panel(_reveal, _card, Vector2(16, 592), Vector2(688, 126), 18)
	Ui.label(_reveal, "الأسرع", 20, Vector2(16, 588), 688, _accent, 900, HORIZONTAL_ALIGNMENT_CENTER, 32)
	for i in 3:
		var y := 618.0 + i * 33.0
		var row := Ui.panel(_reveal, _panel, Vector2(28, y), Vector2(664, 31), 10)
		Ui.panel(row, Ui.MEDALS[i], Vector2(636, 4), Vector2(23, 23), 11)
		Ui.label(row, str(i + 1), 15, Vector2(636, 4), 23, _bg, 900, HORIZONTAL_ALIGNMENT_CENTER, 23)
		var av := _avatar(row, Vector2(606, 3), 25, Ui.AVATAR_BG, 0)
		var nm := Ui.label(row, "", 20, Vector2(330, 0), 270, Color.WHITE, 800, RIGHT, 31)
		var tm := Ui.label(row, "", 16, Vector2(120, 0), 200, Ui.MUTED, 700, RIGHT, 31)
		var pts := Ui.label(row, "", 20, Vector2(10, 0), 100, Ui.GOOD, 900, LEFT, 31)
		_fast_rows.append({"root": row, "avatar": av, "name": nm, "time": tm, "points": pts})
	_fast_rows[0]["empty"] = Ui.label(_reveal, "ما حدا جاوب صح هالمرة", 23, Vector2(16, 624), 688, Ui.MUTED, 600,
			HORIZONTAL_ALIGNMENT_CENTER, 90)


func _build_board() -> void:
	_board = Ui.layer(_ui)
	Ui.label(_board, "ترتيب البث", 40, Vector2(0, -4), W, _accent, 800, HORIZONTAL_ALIGNMENT_CENTER, 60)
	_board_sub = Ui.label(_board, "", 20, Vector2(0, 46), W, Ui.MUTED, 800, HORIZONTAL_ALIGNMENT_CENTER, 32)
	var heights := [96.0, 70.0, 50.0]
	var xs := [255.0, 485.0, 25.0]           # 1st in the middle, 2nd right, 3rd left
	for i in 3:
		var col := Ui.layer(_board)
		var x: float = xs[i]
		var base_top: float = 334.0 - heights[i]
		var d := 84.0 if i == 0 else 70.0
		var av := _avatar(col, Vector2(x + (210 - d) / 2, base_top - d - 58), d, Ui.MEDALS[i], 4)
		var nm := Ui.label(col, "", 22, Vector2(x, base_top - 60), 210, Color.WHITE, 900, HORIZONTAL_ALIGNMENT_CENTER, 32)
		var sc := Ui.label(col, "", 20, Vector2(x, base_top - 30), 210, Ui.MEDALS[i], 900, HORIZONTAL_ALIGNMENT_CENTER, 30)
		Ui.panel(col, Ui.MEDALS[i], Vector2(x, base_top), Vector2(210, heights[i] + 14), 14)
		Ui.label(col, str(i + 1), 36, Vector2(x, base_top), 210, _bg, 800, HORIZONTAL_ALIGNMENT_CENTER, heights[i])
		_podium.append({"root": col, "avatar": av, "name": nm, "score": sc})
	Ui.rect(_board, _bg, Vector2(0, 334), Vector2(W, 14))
	for i in 7:
		var y := 344.0 + i * 46.0
		var row := Ui.panel(_board, _card, Vector2(16, y), Vector2(688, 42), 12)
		Ui.label(row, str(i + 4), 21, Vector2(646, 0), 36, Color(1, 1, 1, 0.75), 900, HORIZONTAL_ALIGNMENT_CENTER, 42)
		var av := _avatar(row, Vector2(608, 5), 32, Ui.AVATAR_BG, 0)
		var nm := Ui.label(row, "", 21, Vector2(250, 0), 350, Color.WHITE, 800, RIGHT, 42)
		var cr := Ui.label(row, "", 18, Vector2(130, 0), 116, Ui.MUTED, 800, HORIZONTAL_ALIGNMENT_CENTER, 42)
		var sc := Ui.label(row, "", 21, Vector2(12, 0), 116, _accent, 900, LEFT, 42)
		_board_rows.append({"root": row, "avatar": av, "name": nm, "correct": cr, "score": sc})
	Ui.rect(_board, _bar, Vector2(0, 668), Vector2(W, 52))
	Ui.label(_board, "مش بالقائمة؟ كل جواب صح بيقرّبك", 20, Vector2(300, 668), 404, Color.WHITE, 900, RIGHT, 52)
	_board_clock = Ui.label(_board, "", 18, Vector2(16, 668), 280, Ui.MUTED, 800, LEFT, 52)


func _build_break() -> void:
	_break = Ui.layer(_ui)
	Ui.label(_break, title, 34, Vector2(130, -2), 574, _accent, 800, RIGHT, 52)
	Ui.label(_break, "الجولة الجاية بتبلّش بعد", 20, Vector2(130, 42), 574, Ui.MUTED, 800, RIGHT, 32)
	Ui.panel(_break, _bg, Vector2(16, 8), Vector2(96, 96), 48, _accent, 5)
	_break_clock = Ui.label(_break, "", 36, Vector2(16, 8), 96, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_CENTER, 96)

	Ui.label(_break, "تصنيفات الجولة الجاية", 19, Vector2(130, 76), 574, Color(1, 1, 1, 0.85), 900, RIGHT, 32)
	_cat_box = HBoxContainer.new()
	_cat_box.position = Vector2(16, 112)
	_cat_box.size = Vector2(688, 38)
	_cat_box.layout_direction = Control.LAYOUT_DIRECTION_RTL
	_cat_box.add_theme_constant_override("separation", 8)
	_break.add_child(_cat_box)

	Ui.panel(_break, Color("#2a2210"), Vector2(16, 158), Vector2(688, 76), 20, _accent, 3)
	_champ_avatar = _avatar(_break, Vector2(630, 166), 60, _accent, 3)
	_champ_title = Ui.label(_break, "", 18, Vector2(200, 158), 420, _accent, 800, RIGHT, 28)
	_champ_name = Ui.label(_break, "", 27, Vector2(200, 184), 420, Color.WHITE, 900, RIGHT, 44)
	_champ_score = Ui.paragraph(_break, "", 19, Vector2(28, 160), Vector2(170, 72), Color.WHITE, 900)

	Ui.panel(_break, _card, Vector2(16, 242), Vector2(688, 66), 18)
	Ui.paragraph(_break, "اكتب بالتعليق A أو B أو C أو D · أول جواب بس بيحسب\nكل ما جاوبت صح أسرع نقاطك بتزيد", 20,
			Vector2(28, 244), Vector2(664, 62))

	Ui.label(_break, "مجاناً", 19, Vector2(16, 310), 688, Color(1, 1, 1, 0.85), 900, RIGHT, 32)
	var free := [["50 لايك", "حذف جواب غلط للكل", Ui.LIKE], ["فولو", "تغيير جوابك مرة", Ui.BLUE],
			["شير", "نقاطك ضعفين", Ui.GOOD]]
	for i in 3:
		var x := 16.0 + (2 - i) * 232.0
		Ui.panel(_break, _card, Vector2(x, 342), Vector2(224, 62), 16)
		Ui.label(_break, free[i][0], 22, Vector2(x, 340), 224, free[i][2], 900, HORIZONTAL_ALIGNMENT_CENTER, 34)
		Ui.label(_break, free[i][1], 19, Vector2(x, 372), 224, Color(1, 1, 1, 0.9), 800, HORIZONTAL_ALIGNMENT_CENTER, 30)

	Ui.label(_break, "الهدايا", 19, Vector2(16, 406), 688, Color(1, 1, 1, 0.85), 900, RIGHT, 32)
	for i in GIFT_ROWS.size():
		var g: Array = GIFT_ROWS[i]
		var y := 438.0 + i * 82.0
		var row := Ui.panel(_break, _card, Vector2(16, y), Vector2(688, 76), 16)
		Ui.rect(row, g[4], Vector2(682, 12), Vector2(6, 52))
		Ui.panel(row, _bg, Vector2(612, 14), Vector2(52, 48), 12)
		Ui.label(row, g[0], 20, Vector2(612, 14), 52, g[4], 900, HORIZONTAL_ALIGNMENT_CENTER, 48)
		Ui.label(row, "%s  ·  %s" % [g[1], g[2]], 20, Vector2(14, 2), 590, g[4], 900, RIGHT, 36)
		Ui.label(row, g[3], 19, Vector2(14, 38), 590, Color.WHITE, 800, RIGHT, 34)

	Ui.label(_break, "الترتيب بيبلّش من الصفر مع كل بث", 17, Vector2(0, 686), W, Color(1, 1, 1, 0.75), 800,
			HORIZONTAL_ALIGNMENT_CENTER, 30)


func _build_overlay() -> void:
	_popup = Ui.panel(_ui, Color("#3b1d4a"), Vector2(24, 230), Vector2(672, 150), 26, _accent, 4)
	_popup.pivot_offset = Vector2(336, 75)
	_popup_text = Ui.paragraph(_popup, "", 32, Vector2(16, 6), Vector2(640, 138), _accent, 800)
	_popup.visible = false
	_status = Ui.label(_ui, "", 13, Vector2(8, Ui.H - 22), 120, Color.WHITE, 500, LEFT, 22)
