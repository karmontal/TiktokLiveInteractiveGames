extends Node2D
## Tug of war screen (720x720, square so TikTok's comments sit under it). Rules live in TugLogic.gd; this file only draws.
## Team A is on the right (read first in Arabic), team B on the left.

const TugLogic := preload("res://games/tug_of_war/TugLogic.gd")

const W := 720.0
const H := 720.0
const ROUND_S := 180.0
const RESULT_S := 8.0
const RANGE := 280.0          # px from the center to a win line
const ROPE_Y := 364.0
const MAX_SHOWN := 10         # avatars shown per team
const FEED_LINES := 3
const TEAM_COLORS := [Color("#3b82f6"), Color("#ef4444")]
const TEAM_NAME_PAIRS := [["قطط", "كلاب"], ["شاي", "قهوة"], ["صيف", "شتا"], ["بحر", "جبل"]]
const FONT_PATH := "res://assets/fonts/Cairo.ttf"
const BOTS_MIN := 5           # filler players at the start of each round (user arg --no-bots turns off)
const BOTS_MAX := 10

var logic := TugLogic.new()
var bots_enabled := not ("--no-bots" in OS.get_cmdline_user_args())
var phase := "play"
var time_left := ROUND_S
var round_no := 0
var team_names: Array = TEAM_NAME_PAIRS[0]

var _ui: Control
var _bold: FontVariation
var _rope_shown := 0.0
var _shake := 0.0
var _name_labels: Array[Label] = []
var _count_labels: Array[Label] = []
var _boost_labels: Array[Label] = []
var _groups: Array[Control] = []
var _group_x: Array[float] = []
var _chips: Array[Dictionary] = [{}, {}]   # team -> {user_id: chip}
var _order: Array[Array] = [[], []]        # team -> user ids, newest first
var _timer_label: Label
var _knot: ColorRect
var _feed: VBoxContainer
var _popup: Label
var _popup_tween: Tween
var _result: Control
var _result_title: Label
var _result_body: Label
var _status: Label


func _ready() -> void:
	Music.play("tug_energy")
	_build_ui()
	EventBus.event_received.connect(_on_event)
	EventBus.connection_changed.connect(_on_connection)
	AvatarCache.avatar_ready.connect(_on_avatar)
	_on_connection(EventBus.connected)
	_apply_team_names()
	_spawn_bots()


func _process(delta: float) -> void:
	_apply(logic.tick(delta), "")
	time_left -= delta
	if phase == "play" and (logic.winner() != TugLogic.NONE or time_left <= 0.0):
		_end_round()
	elif phase == "result" and time_left <= 0.0:
		_new_round()

	_rope_shown = lerpf(_rope_shown, logic.rope, minf(1.0, delta * 6.0))
	var offset := -_rope_shown * RANGE        # rope -1 (A wins) moves everything right
	_knot.position.x = W / 2.0 + offset - _knot.size.x / 2.0
	for t in 2:
		_groups[t].position.x = _group_x[t] + offset * 0.35
		_boost_labels[t].visible = logic.boosted(t)
	var secs := maxi(0, ceili(time_left))
	_timer_label.text = "%d:%02d" % [secs / 60, secs % 60] if phase == "play" else ""

	if _shake > 0.0:
		_shake -= delta
		position = Vector2(randf_range(-10, 10), randf_range(-10, 10))
	else:
		position = Vector2.ZERO


# ---------------------------------------------------------------- events

func _on_event(ev: Dictionary) -> void:
	var name := _user_name(ev.get("user"))
	_apply(logic.handle(ev), name)
	if ev.get("type") == "follow" and ev.get("user") is Dictionary:
		var uid := str(ev["user"].get("id", ""))
		if logic.team_of.has(uid):
			_say("%s عمل فولو: شدّة قوية" % name, logic.team_of[uid])


## Shows what TugLogic says happened. Bots get avatars and flashes but no feed lines.
func _apply(effects: Array[Dictionary], name: String) -> void:
	if effects.is_empty():
		return
	for fx in effects:
		var team: int = fx["team"]
		var bot := TugLogic.is_bot(str(fx["user"].get("id", "")))
		match fx["kind"]:
			"left":
				_remove_chip(str(fx["user"].get("id", "")), team)
			"joined":
				_add_chip(fx["user"], team)
				if not bot:
					var verb := "انتقل لفريق" if fx["switched"] else "انضم لفريق"
					_say("%s %s %s" % [_user_name(fx["user"]), verb, team_names[team]], team)
			"pull":
				_flash_chip(str(fx["user"]["id"]), team)
			"boost":
				_say("%s عمل شير: قوة %s ×2" % [name, team_names[team]], team)
			"gift":
				var gift: Dictionary = fx["gift"]
				_say("%s بعت %s ×%d" % [name, gift.get("name", "هدية"), fx["count"]], team)
				var tier: String = gift.get("tier", "small")
				if tier != "small":
					_show_popup("%s\n%s ×%d" % [name, gift.get("name", ""), fx["count"]], TEAM_COLORS[team])
				if tier == "large":
					_shake = 0.6
	for t in 2:
		_count_labels[t].text = "%d لاعب" % logic.team_count(t)


func _on_connection(connected: bool) -> void:
	_status.text = "● متصل" if connected else "● غير متصل"
	_status.add_theme_color_override("font_color", Color("#3ddc84") if connected else Color("#ff5c5c"))


func _on_avatar(user_id: String, texture: Texture2D) -> void:
	for t in 2:
		if _chips[t].has(user_id):
			var chip: Control = _chips[t][user_id]
			chip.get_node("Avatar").texture = texture
			chip.get_node("Initial").visible = false


# ---------------------------------------------------------------- rounds

func _end_round() -> void:
	phase = "result"
	time_left = RESULT_S
	logic.active = false
	var winner := logic.winner()
	if winner == TugLogic.NONE:
		winner = logic.leader()
	if winner == TugLogic.NONE:
		_result_title.text = "تعادل!"
		_result_title.add_theme_color_override("font_color", Color.WHITE)
	else:
		_result_title.text = "فاز فريق %s!" % team_names[winner]
		_result_title.add_theme_color_override("font_color", TEAM_COLORS[winner].lightened(0.3))
	var lines: PackedStringArray = []
	for t in [TugLogic.A, TugLogic.B]:
		var mvp := logic.mvp(t)
		if not mvp.is_empty():
			lines.append("نجم %s: %s" % [team_names[t], _user_name(mvp["user"])])
	lines.append("")
	lines.append("جولة جديدة بعد لحظات...")
	_result_body.text = "\n".join(lines)
	_result.visible = true


func _new_round() -> void:
	round_no += 1
	team_names = TEAM_NAME_PAIRS[round_no % TEAM_NAME_PAIRS.size()]
	_apply_team_names()
	logic.new_round()
	_spawn_bots()
	phase = "play"
	time_left = ROUND_S
	_result.visible = false


func _spawn_bots() -> void:
	if bots_enabled:
		_apply(logic.spawn_bots(randi_range(BOTS_MIN, BOTS_MAX)), "")


func _apply_team_names() -> void:
	_name_labels[TugLogic.A].text = "A • %s" % team_names[TugLogic.A]
	_name_labels[TugLogic.B].text = "B • %s" % team_names[TugLogic.B]


# ---------------------------------------------------------------- avatars

func _add_chip(user: Dictionary, team: int) -> void:
	var uid := str(user["id"])
	var other := 1 - team
	if _chips[other].has(uid):
		_chips[other][uid].queue_free()
		_chips[other].erase(uid)
		_order[other].erase(uid)
	if not _chips[team].has(uid):
		_chips[team][uid] = _make_chip(user, team)
		_groups[team].add_child(_chips[team][uid])
	_order[team].erase(uid)
	_order[team].push_front(uid)
	while _order[team].size() > MAX_SHOWN:
		var old: String = _order[team].pop_back()
		_chips[team][old].queue_free()
		_chips[team].erase(old)
	_layout(other)
	_layout(team)


func _remove_chip(uid: String, team: int) -> void:
	if not _chips[team].has(uid):
		return
	_chips[team][uid].queue_free()
	_chips[team].erase(uid)
	_order[team].erase(uid)
	_layout(team)


func _layout(team: int) -> void:
	for i in _order[team].size():
		var chip: Control = _chips[team][_order[team][i]]
		chip.position = Vector2((i % 5) * 66, (i / 5) * 84)


func _make_chip(user: Dictionary, team: int) -> Control:
	var chip := Control.new()
	chip.size = Vector2(64, 74)
	var avatar := TextureRect.new()
	avatar.name = "Avatar"
	avatar.position = Vector2(7, 0)
	avatar.size = Vector2(50, 50)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var tex := AvatarCache.get_avatar(str(user["id"]), str(user.get("avatar", "")))
	avatar.texture = tex if tex else AvatarCache.placeholder(TEAM_COLORS[team])
	chip.add_child(avatar)
	var initial := _label(_user_name(user).left(1).to_upper(), 24, Vector2(7, 2), 50, Color.WHITE, true, chip)
	initial.name = "Initial"
	initial.visible = tex == null
	var nm := _label(_user_name(user), 16, Vector2(-2, 48), 68, Color.WHITE, true, chip)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return chip


func _flash_chip(uid: String, team: int) -> void:
	if not _chips[team].has(uid):
		return
	var chip: Control = _chips[team][uid]
	chip.modulate = Color(1.6, 1.6, 1.0)
	create_tween().tween_property(chip, "modulate", Color.WHITE, 0.4)


# ---------------------------------------------------------------- feed & popup

func _say(text: String, team: int) -> void:
	var line := _label(text, 22, Vector2.ZERO, W - 40, TEAM_COLORS[team].lightened(0.45), false, _feed)
	line.clip_text = true
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	while _feed.get_child_count() > FEED_LINES:
		var first := _feed.get_child(0)
		_feed.remove_child(first)
		first.queue_free()


func _show_popup(text: String, color: Color) -> void:
	_popup.text = text
	_popup.add_theme_color_override("font_outline_color", color.darkened(0.5))
	_popup.visible = true
	_popup.scale = Vector2(0.4, 0.4)
	_popup.modulate.a = 1.0
	if _popup_tween:
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.tween_property(_popup, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tween.tween_interval(2.2)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.4)
	_popup_tween.tween_callback(func(): _popup.visible = false)


# ---------------------------------------------------------------- building

func _user_name(user) -> String:
	if user is Dictionary:
		return str(user.get("name", "?"))
	return "?"


func _label(text: String, font_size: int, pos: Vector2, width: float, color := Color.WHITE,
		bold := false, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(width, font_size * 1.7)
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_direction = Control.TEXT_DIRECTION_RTL  # "Omar بعت Lion" must read right to left
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", _bold)
	(parent if parent else _ui).add_child(l)
	return l


func _rect(color: Color, pos: Vector2, rect_size: Vector2, parent: Node = null) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = rect_size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else _ui).add_child(r)
	return r


func _build_ui() -> void:
	var font: FontFile = load(FONT_PATH)
	var regular := FontVariation.new()
	regular.base_font = font
	regular.variation_opentype = {"weight": 500}
	_bold = FontVariation.new()
	_bold.base_font = font
	_bold.variation_opentype = {"weight": 800}

	_ui = Control.new()
	_ui.size = Vector2(W, H)
	_ui.theme = Theme.new()
	_ui.theme.default_font = regular
	add_child(_ui)

	_rect(Color("#0f0b24"), Vector2.ZERO, Vector2(W, H))
	_rect(Color(TEAM_COLORS[TugLogic.A], 0.10), Vector2(W / 2, 0), Vector2(W / 2, H))
	_rect(Color(TEAM_COLORS[TugLogic.B], 0.10), Vector2.ZERO, Vector2(W / 2, H))

	_label("شدّ الحبل", 44, Vector2(0, -6), W, Color("#ffd23f"), true)
	# How to play, at the top and large: TikTok's comments cover the bottom, and phones are small.
	_rect(Color(0, 0, 0, 0.5), Vector2(0, 64), Vector2(W, 112))
	_label("اكتب A أو B وانضم لفريقك", 25, Vector2(0, 58), W, Color.WHITE, true)
	var help := ["لايك = شدّة", "فولو = شدّة قوية", "شير = قوة ضعفين", "هدية = شدّة كبيرة"]
	for i in help.size():
		var pos := Vector2(W / 2 + 6 if i % 2 == 0 else 12.0, 102.0 + (i / 2) * 36.0)
		_rect(Color(1, 1, 1, 0.08), pos, Vector2(W / 2 - 18, 32))
		_label(help[i], 20, pos + Vector2(0, -2), W / 2 - 18, Color.WHITE, true)

	for t in 2:
		var x := W / 2 + 10 if t == TugLogic.A else 20.0
		_rect(Color(TEAM_COLORS[t], 0.35), Vector2(x, 182), Vector2(330, 76))
		_name_labels.append(_label("", 32, Vector2(x, 176), 330, Color.WHITE, true))
		_count_labels.append(_label("0 لاعب", 22, Vector2(x, 218), 330, Color(1, 1, 1, 0.9), true))
		var boost := _label("×2", 28, Vector2(x + 254, 176), 76, Color("#ffd23f"), true)
		boost.visible = false
		_boost_labels.append(boost)

	_timer_label = _label("", 34, Vector2(0, 258), W, Color.WHITE, true)

	var rope := Line2D.new()
	rope.points = PackedVector2Array([Vector2(10, ROPE_Y), Vector2(W - 10, ROPE_Y)])
	rope.width = 14
	rope.default_color = Color("#c8a46b")
	_ui.add_child(rope)
	_rect(Color(1, 1, 1, 0.6), Vector2(W / 2 - 2, ROPE_Y - 44), Vector2(4, 88))
	for t in 2:
		var line_x := W / 2 + (-RANGE if t == TugLogic.B else RANGE)
		_rect(TEAM_COLORS[t], Vector2(line_x - 4, ROPE_Y - 56), Vector2(8, 112))
	_knot = _rect(Color("#ffd23f"), Vector2(W / 2 - 14, ROPE_Y - 36), Vector2(28, 72))

	for t in 2:
		var gx := W / 2 + 10 if t == TugLogic.A else 22.0
		var group := Control.new()
		group.position = Vector2(gx, 432)
		group.size = Vector2(330, 168)
		_ui.add_child(group)
		_groups.append(group)
		_group_x.append(gx)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(20, 606)
	_feed.size = Vector2(W - 40, 112)
	_feed.add_theme_constant_override("separation", -4)
	_ui.add_child(_feed)

	_popup = _label("", 46, Vector2(0, 250), W, Color.WHITE, true)
	_popup.size.y = 170
	_popup.pivot_offset = Vector2(W / 2, 85)
	_popup.add_theme_constant_override("outline_size", 16)
	_popup.visible = false

	_result = Control.new()
	_result.size = Vector2(W, H)
	_result.visible = false
	_ui.add_child(_result)
	_rect(Color(0, 0, 0, 0.8), Vector2.ZERO, Vector2(W, H), _result)
	_result_title = _label("", 64, Vector2(0, 180), W, Color.WHITE, true, _result)
	_result_body = _label("", 32, Vector2(0, 310), W, Color.WHITE, true, _result)
	_result_body.size.y = 260

	_status = _label("", 18, Vector2(12, 4), 160, Color.WHITE, false)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
