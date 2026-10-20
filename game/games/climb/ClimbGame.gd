extends Node2D
## Tower climb screen (720x720, square so TikTok's comments sit under it). Rules live in ClimbLogic.gd, the camera's choices in
## CameraDirector.gd; this file only draws. Look: the "تسلّق البرج — الأشكال" design canvas.
## Every 25 floors is a zone with its own sky, wall and ledges (foothills, rocks, ice, clouds);
## the minimap on the left shows the whole tower in the same colors.

const ClimbLogic := preload("res://games/climb/ClimbLogic.gd")
const CameraDirector := preload("res://games/climb/CameraDirector.gd")
const Ui := preload("res://core/Ui.gd")

const W := 720.0
const H := 720.0
const LEFT := HORIZONTAL_ALIGNMENT_LEFT
const RIGHT := HORIZONTAL_ALIGNMENT_RIGHT
const CENTER := HORIZONTAL_ALIGNMENT_CENTER
const VIEW_Y := 206.0            # the world view, under the header, help bar and leaders
const VIEW_H := H - VIEW_Y
const FLOOR_PX := 110.0
const TARGET_AT := 2.2           # floors between the bottom of the view and what the camera shows
const TOWER_L := 112.0
const TOWER_R := 708.0
const LEDGE_L := 122.0
const LEDGE_R := 698.0
const SLOTS := 8                 # climbers spread over 8 spots per floor
const MAX_SHOWN := 30            # climbers drawn at once (the minimap shows everyone)
const MAP_POS := Vector2(12, 214)
const MAP_SIZE := Vector2(80, 380)
const MAP_TRACK := Rect2(32, 40, 12, 328)
const FEED_LINES := 3
const GOLD := Color("#ffd23f")
const WINGS := Color("#5eead4")
const DANGER := Color("#ff8a8a")
const LIKE := Color("#ff6b8f")
const MUTED := Color("#b8c2d0")
const ZONES := [
	{"name": "السفح", "key": "#4ade80", "sky": ["#1d2b4f", "#2d4a5a"], "wall": "#4a3a2a",
		"edge": ["#5c4a36", "#33281c"], "top": "#65a30d", "front": "#5b3d22", "mile": "#a3e635"},
	{"name": "الصخور", "key": "#9aa5b1", "sky": ["#13294a", "#23404d"], "wall": "#2b3540",
		"edge": ["#3d4954", "#1c242c"], "top": "#8e99a5", "front": "#56616c", "mile": "#c9d2db"},
	{"name": "الجليد", "key": "#7dd3fc", "sky": ["#0b2140", "#1e4f7a"], "wall": "#285a80",
		"edge": ["#4a86b0", "#1b3f5c"], "top": "#f0f9ff", "front": "#7dd3fc", "mile": "#ffffff"},
	{"name": "السحاب", "key": "#b9b3ff", "sky": ["#120624", "#2e1a5c"], "wall": "#b9b3ff1f",
		"edge": ["#b9b3ff4d", "#b9b3ff26"], "top": "#ffffff", "front": "#b9b3ff", "mile": "#ffffff"},
]
const PLAYER_COLORS := [["#7c3aed", "#a78bfa"], ["#0e7490", "#22d3ee"], ["#15803d", "#4ade80"],
	["#b45309", "#fb923c"], ["#be185d", "#f472b6"], ["#1d4ed8", "#60a5fa"], ["#a16207", "#facc15"],
	["#334155", "#94a3b8"]]
const SHOT_TEXT := {"leader": "المتصدّر", "second": "الثاني", "climber": "على البرج"}
const HELP := [["لايك", "نطّة لفوق", "heart", "#ff6b8f"], ["فولو", "نقطة حفظ", "flag", "#3ddc84"],
	["شير", "جناحين", "wings", "#5eead4"], ["هدية", "طوابق", "gift", "#c084fc"],
	["هدية كبيرة", "ترفع الكل", "rocket", "#ffd23f"]]
# Shapes, drawn from point lists
const WING := [Vector2(40, 26), Vector2(32, 12), Vector2(20, 3), Vector2(8, 1), Vector2(0, 6),
	Vector2(8, 11), Vector2(11, 18), Vector2(8, 30), Vector2(18, 27), Vector2(28, 29), Vector2(40, 34)]
const CROWN := [Vector2(2, 20), Vector2(4, 4), Vector2(12, 12), Vector2(18, 2), Vector2(24, 12),
	Vector2(32, 4), Vector2(34, 20)]
const ROCK := [Vector2(6, 14), Vector2(16, 4), Vector2(30, 6), Vector2(38, 18), Vector2(33, 33),
	Vector2(18, 38), Vector2(5, 30)]
const FLAG := [Vector2(0, 0), Vector2(26, 0), Vector2(19, 10), Vector2(26, 20), Vector2(0, 20)]
const STAR := [Vector2(12, 0), Vector2(15, 8), Vector2(24, 8), Vector2(17, 13), Vector2(20, 22),
	Vector2(12, 16), Vector2(4, 22), Vector2(7, 13), Vector2(0, 8), Vector2(9, 8)]

var logic := ClimbLogic.new()
var director := CameraDirector.new()

var _ui: Control
var _bg: Control
var _world: Control
var _tower: Control
var _marks: Control                      # checkpoint flags, the camera's arrow
var _fx: Control                         # rocks, beams, floating numbers
var _climbers := {}                      # uid -> {"node", "holder", "crown", "shown", "slot", "hop", "colors"}
var _shown_ids: Array = []
var _refresh_left := 0.0
var _cam := 0.0
var _sky := [Color("#1d2b4f"), Color("#2d4a5a")]
var _shot := {}
var _caption: Panel
var _caption_text: Label
var _zone_badge: Panel
var _zone_dot: ColorRect
var _zone_text: Label
var _band: Control
var _band_pill: Panel
var _band_text: Label
var _blink := 0.0
var _map: Control
var _leaders: Array[Dictionary] = []     # header chips
var _timer: Label
var _count: Label
var _feed: VBoxContainer
var _popup: Panel
var _popup_text: Label
var _popup_tween: Tween
var _shake := 0.0
var _boxes := {}                         # cached StyleBoxFlat by "color/radius"
var _result: Control
var _res_round: Label
var _res_title: Label
var _res_stage: Control
var _res_climber: Dictionary = {}
var _res_platform: Label
var _res_name: Label
var _res_stats: Label
var _res_rows: Array[Dictionary] = []
var _hall: Array[Dictionary] = []
var _res_clock: Label
var _confetti: Array[ColorRect] = []
var _status: Label
var _users := {}                         # uid -> user, for avatars that load later


func _ready() -> void:
	Music.play("climb_adventure")
	_ui = Ui.root(self)
	_bg = _canvas(_ui, Vector2.ZERO, Vector2(W, H), _draw_bg)
	_build_world()
	_build_map()
	_build_header()
	_build_bottom()
	_build_result()
	EventBus.event_received.connect(_on_event)
	EventBus.connection_changed.connect(_on_connection)
	AvatarCache.avatar_ready.connect(_on_avatar)
	_on_connection(EventBus.connected)
	_apply(logic.start())


func _process(delta: float) -> void:
	_apply(logic.tick(delta))
	if logic.phase == "climb":
		var before: String = "%s/%s" % [_shot.get("kind", ""), _shot.get("uid", "")]
		_shot = director.tick(delta, logic)
		if "%s/%s" % [_shot.get("kind", ""), _shot.get("uid", "")] != before:
			_refresh_left = 0.0          # new shot: caption and climbers right away
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		_refresh_shown()
		_refresh_leaders()
		_refresh_caption()

	var focus: float = _shot.get("floor", 0.0)
	var target := clampf(focus - TARGET_AT, -1.3, logic.top_floor - VIEW_H / FLOOR_PX + 0.8)   # below 0: the ground shows
	var diff := target - _cam
	var step := maxf(absf(diff) * minf(1.0, delta * 3.5), 8.0 * delta)   # eases out, but never crawls
	_cam += clampf(diff, -step, step)
	var zone: Dictionary = ZONES[_zone(maxf(_cam, 0.0) + 4.0)]
	for i in 2:
		_sky[i] = _sky[i].lerp(Color(zone["sky"][i]), minf(1.0, delta * 2.0))
	_zone_dot.color = Color(zone["key"])
	_zone_text.text = "منطقة %s" % zone["name"]
	Ui.restyle(_zone_badge, Color(0.02, 0.03, 0.08, 0.72), Color(zone["key"]), 1)

	for uid in _shown_ids:
		var c: Dictionary = _climbers[uid]
		c["shown"] = lerpf(c["shown"], logic.floor_of.get(uid, 0.0), minf(1.0, delta * 5.0))
		c["hop"] = maxf(0.0, c["hop"] - delta * 3.0)
		c["node"].position = Vector2(_slot_x(c["slot"]), _y(c["shown"]) - 106.0 - sin(c["hop"] * PI) * 34.0)
		c["node"].queue_redraw()

	_blink += delta
	_band.visible = not logic.hazard.is_empty()
	_band_pill.visible = _band.visible
	if _band.visible:
		var top := _y(logic.hazard["to"]) - 70.0
		_band.position.y = top
		_band.size.y = (logic.hazard["to"] - logic.hazard["from"]) * FLOOR_PX + 70.0
		_band.modulate.a = 0.75 + 0.25 * sin(_blink * 10.0)
		_band_pill.position.y = clampf(top + 12.0, 62.0, VIEW_H - 60.0)   # under the zone badge
		_band_text.text = "صخور نازلة بعد %d" % ceili(logic.hazard["in"])

	var secs := maxi(0, ceili(logic.time_left))
	_timer.text = "%d:%02d" % [secs / 60, secs % 60] if logic.phase == "climb" else "--:--"
	if logic.phase == "result":
		_res_clock.text = "جولة جديدة بعد %d" % secs
	_bg.queue_redraw()
	_tower.queue_redraw()
	_marks.queue_redraw()
	_map.queue_redraw()

	if _shake > 0.0:
		_shake -= delta
		position = Vector2(randf_range(-9, 9), randf_range(-9, 9))
	else:
		position = Vector2.ZERO


# ---------------------------------------------------------------- events

func _on_event(ev: Dictionary) -> void:
	_apply(logic.handle(ev))


func _apply(effects: Array[Dictionary]) -> void:
	for fx in effects:
		match fx["kind"]:
			"round_start":
				_result.visible = false
				director.reset()
				for uid in _climbers:
					_climbers[uid]["shown"] = 0.0
				_say("الجولة %d بلّشت! أول واحد بيوصل للقمة بيفوز" % fx["round"], GOLD, "flag")
			"joined":
				_users[str(fx["user"]["id"])] = fx["user"]
				if logic.phase == "climb":
					director.joined(fx["user"])
			"climb":
				var uid := str(fx["user"]["id"])
				if _climbers.has(uid):
					_climbers[uid]["hop"] = 1.0
			"checkpoint":
				_say("%s عمل فولو: نقطة حفظ على طابق %d" % [_name(fx["user"]), fx["floor"]], Ui.GOOD, "flag")
			"wings":
				_say("%s عمل شير: جناحين ضد الصخرة الجاية" % _name(fx["user"]), WINGS, "wings")
			"gift":
				var gift: Dictionary = fx["gift"]
				_say("هدية من %s: طلع %d طوابق" % [_name(fx["user"]), fx["floors"]], Ui.PURPLE, "gift")
				if gift.get("tier", "small") == "medium":
					_show_popup("%s\n%s ×%d" % [_name(fx["user"]), gift.get("name", ""), fx["count"]])
			"lift_all":
				_show_popup("%s رفع الكل!\n+%d طوابق لكل المتسلقين" % [_name(fx["user"]), fx["floors"]])
				_beam()
				_shake = 0.6
			"hazard_warning":
				director.hazard(fx["from"], fx["to"], logic.hazard_warning_s)
			"hazard_strike":
				_strike(fx)
			"summit":
				_say("%s وصل للقمة!" % _name(fx["user"]), GOLD, "crown")
			"round_end":
				_show_result(fx)
	_count.text = "%d متسلّق" % logic.floor_of.size()


func _on_connection(connected: bool) -> void:
	_status.text = "● متصل" if connected else "● غير متصل"
	_status.add_theme_color_override("font_color", Ui.GOOD if connected else Color("#ff5c5c"))


func _on_avatar(user_id: String, texture: Texture2D) -> void:
	var holders: Array = _leaders.map(func(l): return l["holder"])
	holders.append_array(_res_rows.map(func(r): return r["holder"]))
	holders.append_array(_hall.map(func(h): return h["holder"]))
	holders.append(_res_climber["holder"])
	if _climbers.has(user_id):
		holders.append(_climbers[user_id]["holder"])
	for holder in holders:
		if holder.get_meta("uid", "") == user_id:
			Ui.set_avatar(holder, _users.get(user_id, {}), texture)


func _set_avatar(holder: Panel, user: Dictionary) -> void:
	var uid := str(user.get("id", ""))
	_users[uid] = user
	Ui.set_avatar(holder, user, AvatarCache.get_avatar(uid, str(user.get("avatar", ""))))


func _name(user) -> String:
	return str(user.get("name", "?")) if user is Dictionary else "?"


# ---------------------------------------------------------------- camera caption

func _refresh_caption() -> void:
	var kind: String = _shot.get("kind", "")
	var text := ""
	var color := Color.WHITE
	match kind:
		"join":
			var users: Array = _shot["users"]
			var names: Array = users.slice(0, 2).map(func(u): return _name(u))
			text = "أهلا بـ %s" % " و".join(names)
			if users.size() > 2:
				text += " و%d كمان" % (users.size() - 2)
			color = Ui.GOOD
		"ground":
			text = "اعمل لايك وابدأ التسلّق!"
			color = LIKE
		"leader", "second", "climber":
			text = "%s: %s" % [SHOT_TEXT[kind], _name(_shot["users"][0])]
			color = GOLD if kind == "leader" else (Color("#cbd5e1") if kind == "second" else Color.WHITE)
		_:
			_caption.visible = false      # rocks have their own warning
			return
	_caption.visible = logic.phase == "climb"
	_caption_text.text = text
	_caption_text.add_theme_color_override("font_color", color)
	Ui.restyle(_caption, Color(0.02, 0.03, 0.08, 0.78), color, 2)


# ---------------------------------------------------------------- world

func _zone(f: float) -> int:
	return clampi(int(f / 25.0), 0, ZONES.size() - 1)


## y inside the world view of the ledge (and the feet) of floor f.
func _y(f: float) -> float:
	return VIEW_H - 60.0 - (f - _cam) * FLOOR_PX


func _slot_x(slot: int) -> float:
	return LEDGE_L + 14.0 + slot * (LEDGE_R - LEDGE_L - 120.0 - 76.0) / (SLOTS - 1)


func _colors(uid: String) -> Array:
	return PLAYER_COLORS[absi(hash(uid)) % PLAYER_COLORS.size()]


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var key := "%s/%d" % [color.to_html(), radius]
	if not _boxes.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(radius)
		_boxes[key] = sb
	return _boxes[key]


func _draw_bg() -> void:
	_bg.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(W, 0), Vector2(W, H), Vector2(0, H)]),
			PackedColorArray([_sky[0], _sky[0], _sky[1], _sky[1]]))
	var stars := clampf((_cam - 20.0) / 40.0, 0.15, 1.0)
	for i in 36:
		var p := Vector2(fmod(i * 97.0, W), fmod(i * 61.0 + _cam * 6.0, H))
		_bg.draw_circle(p, 1.0 + i % 3 * 0.6, Color(1, 1, 1, stars * (0.2 + (i % 5) * 0.1)))


func _draw_tower() -> void:
	var first := int(floor(_cam)) - 1
	var last := first + int(VIEW_H / FLOOR_PX) + 3
	var font := Ui.font(800)
	var gy := _y(0) + 26.0
	if gy < VIEW_H:                                  # the ground under floor 0
		_tower.draw_colored_polygon(PackedVector2Array([Vector2(0, gy + 10), Vector2(120, gy - 20),
				Vector2(260, gy + 4), Vector2(420, gy - 28), Vector2(600, gy + 2), Vector2(W, gy - 16),
				Vector2(W, VIEW_H + 10), Vector2(0, VIEW_H + 10)]), Color("#1f5134"))
	for fl in range(first, last + 1):
		if fl < 0 or fl > int(logic.top_floor):
			continue
		var zi := _zone(fl)
		var z: Dictionary = ZONES[zi]
		var y := _y(fl)
		if fl < int(logic.top_floor):                # wall up to the next ledge
			_tower.draw_rect(Rect2(TOWER_L, y - FLOOR_PX, TOWER_R - TOWER_L, FLOOR_PX), Color(z["wall"]))
			_tower.draw_rect(Rect2(TOWER_L, y - FLOOR_PX, 10, FLOOR_PX), Color(z["edge"][0]))
			_tower.draw_rect(Rect2(TOWER_R - 10, y - FLOOR_PX, 10, FLOOR_PX), Color(z["edge"][1]))
			if zi == 1:
				for k in 3:
					var by := y - FLOOR_PX + 18 + k * 36
					_tower.draw_line(Vector2(TOWER_L + 10, by), Vector2(TOWER_R - 10, by), Color(1, 1, 1, 0.035), 2)
		var summit := fl == int(logic.top_floor)
		var mile := fl % 5 == 0
		var top_c := Color("#ffe68a") if summit else Color(z["mile"] if mile else z["top"])
		var front_c := Color("#c79a10") if summit else Color(z["front"])
		var radius := 13 if zi == 3 else 5
		_tower.draw_rect(Rect2(LEDGE_L, y + 26, LEDGE_R - LEDGE_L, 7), Color(0, 0, 0, 0.25))
		_tower.draw_style_box(_box(front_c, 13 if zi == 3 else 0), Rect2(LEDGE_L, y + 6, LEDGE_R - LEDGE_L, 20))
		_tower.draw_style_box(_box(top_c, radius), Rect2(LEDGE_L, y, LEDGE_R - LEDGE_L, 10))
		if zi == 0:
			for gx in [140.0, 230.0, 330.0, 470.0, 560.0]:
				_tower.draw_colored_polygon(PackedVector2Array([Vector2(gx, y), Vector2(gx + 4, y - 9),
						Vector2(gx + 8, y), Vector2(gx + 11, y - 12), Vector2(gx + 14, y)]), Color("#4ade80"))
		elif zi == 2:
			for ix in [150.0, 250.0, 360.0, 460.0, 580.0]:
				var drop := 12.0 + fmod(ix, 9.0)
				_tower.draw_colored_polygon(PackedVector2Array([Vector2(ix, y + 26), Vector2(ix + 12, y + 26),
						Vector2(ix + 6, y + 26 + drop)]), Color("#e0f2fe"))
		var label := "القمة" if summit else str(fl)
		var bw := 72.0 if summit else 46.0
		var badge := Rect2(LEDGE_R - bw - 12, y - 36, bw, 28)
		_tower.draw_style_box(_box(GOLD if mile or summit else Color(0, 0, 0, 0.45), 14), badge)
		_tower.draw_string(font, Vector2(badge.position.x, badge.position.y + 21), label, CENTER, bw, 16,
				Color("#1a1300") if mile or summit else Color("#cfd8e3"))
		if summit:
			var fx := W / 2.0
			_tower.draw_rect(Rect2(fx - 3, y - 96, 6, 96), Color("#e2e8f0"))
			_tower.draw_colored_polygon(_shape(FLAG, Vector2(fx + 3, y - 94), 2.4), GOLD)
			_tower.draw_colored_polygon(_shape(STAR, Vector2(fx + 18, y - 89), 1.4), Color("#7a5a00"))


func _draw_marks() -> void:
	for uid in _shown_ids:
		var cp: float = logic.checkpoint.get(uid, 0.0)
		if cp <= 0.0:
			continue
		var x := _slot_x(_climbers[uid]["slot"]) + 2.0
		var y := _y(cp)
		if y < -80 or y > VIEW_H + 10:
			continue
		_marks.draw_rect(Rect2(x, y - 62, 4, 62), Color("#d7e2e8"))
		_marks.draw_colored_polygon(_shape(FLAG, Vector2(x + 4, y - 60), 1.0), Ui.GOOD)
	var focus: String = _shot.get("uid", "")
	if focus != "" and _climbers.has(focus):
		var node: Control = _climbers[focus]["node"]
		var c := node.position + Vector2(38, -12 + sin(_blink * 6.0) * 4.0)
		var kind: String = _shot["kind"]
		var color := GOLD if kind == "leader" else (Ui.GOOD if kind == "join" else Color.WHITE)
		_marks.draw_colored_polygon(PackedVector2Array([c + Vector2(-11, -12), c + Vector2(11, -12), c]), color)


func _draw_band() -> void:
	var s := _band.size
	_band.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 0.36, 0.36, 0.12))
	var x := -s.y
	while x < s.x:
		var a := Vector2(x, s.y)
		var b := Vector2(x + s.y, 0)
		if a.x < 0:                                  # keep the stripes inside the band
			a = a.lerp(b, -a.x / (b.x - a.x))
		if b.x > s.x:
			b = a.lerp(b, (s.x - a.x) / (b.x - a.x))
		_band.draw_line(a, b, Color(1, 0.36, 0.36, 0.14), 16)
		x += 40.0
	_band.draw_dashed_line(Vector2(0, 1.5), Vector2(s.x, 1.5), DANGER, 3, 12)
	_band.draw_dashed_line(Vector2(0, s.y - 1.5), Vector2(s.x, s.y - 1.5), DANGER, 3, 12)


## The climber's body; the head is a real avatar, the crown its own little control.
func _draw_climber(node: Control) -> void:
	var uid: String = node.get_meta("uid")
	var shirt: Color = node.get_meta("shirt")
	var cheer: bool = node.get_meta("cheer", false)
	var hop: float = _climbers[uid]["hop"] if _climbers.has(uid) and not cheer else 0.0
	if hop > 0.05:
		node.draw_rect(Rect2(18, 112, 40, 4), Color(1, 1, 1, 0.35 * hop))
		node.draw_rect(Rect2(26, 120, 24, 4), Color(1, 1, 1, 0.2 * hop))
	if logic.wings.has(uid) and not cheer:
		node.draw_colored_polygon(_shape(WING, Vector2(-18, 50), 1.0), WINGS)
		node.draw_colored_polygon(_shape(WING, Vector2(-18, 50), 1.0, 112.0), WINGS)
	var arm := 32.0 if cheer else 16.0
	for side in [-1, 1]:
		node.draw_set_transform(Vector2(38 + side * 20.5, 40.0 if cheer else 50.0), deg_to_rad(side * arm))
		node.draw_style_box(_box(shirt, 5), Rect2(-4.5, -18, 9, 36))
	node.draw_set_transform(Vector2.ZERO)
	node.draw_style_box(_box(shirt, 9), Rect2(25, 63, 26, 27))
	node.draw_style_box(_box(Color("#1b1930"), 4), Rect2(27, 86, 9, 20))
	node.draw_style_box(_box(Color("#1b1930"), 4), Rect2(40, 86, 9, 20))


func _draw_crown(node: Control) -> void:
	node.draw_colored_polygon(_shape(CROWN, Vector2.ZERO, 1.0), GOLD)
	node.draw_polyline(_shape(CROWN + [CROWN[0]], Vector2.ZERO, 1.0), Color("#7a5a00"), 1.5)


## Points scaled and moved; mirror_w > 0 mirrors them inside a box that wide.
func _shape(points: Array, offset: Vector2, k: float, mirror_w := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		var q: Vector2 = p
		if mirror_w > 0.0:
			q.x = mirror_w - q.x
		out.append(offset + q * k)
	return out


## Which climbers get a body: the camera's subject first, then the highest ones in view.
func _refresh_shown() -> void:
	var lo := _cam - 1.5
	var hi := _cam + VIEW_H / FLOOR_PX + 1.0
	var keep := {}
	for u in _shot.get("users", []):
		var uid := str(u["id"])
		if logic.floor_of.has(uid):
			keep[uid] = {"user": u, "floor": logic.floor_of[uid]}
	for entry in logic.ranking():
		if keep.size() >= MAX_SHOWN:
			break
		if entry["floor"] >= lo and entry["floor"] <= hi:
			keep[str(entry["user"]["id"])] = entry
	for uid in _climbers.keys():
		if not keep.has(uid):
			_climbers[uid]["node"].queue_free()
			_climbers.erase(uid)
	var leader := ""
	var top := logic.ranking(1)
	if not top.is_empty() and top[0]["floor"] > 0.0:
		leader = str(top[0]["user"]["id"])
	for uid in keep:
		if not _climbers.has(uid):
			_climbers[uid] = _make_climber(_world, keep[uid]["user"])
			_climbers[uid]["shown"] = keep[uid]["floor"]
			_world.move_child(_climbers[uid]["node"], _fx.get_index())   # under rocks and numbers
		var c: Dictionary = _climbers[uid]
		var ring := Color.WHITE
		if uid == leader:
			ring = GOLD
		elif logic.wings.has(uid):
			ring = WINGS
		Ui.restyle(c["holder"], Color(c["colors"][0]), ring, 3)
		c["crown"].visible = uid == leader
	_shown_ids = keep.keys()


func _make_climber(parent: Control, user: Dictionary) -> Dictionary:
	var uid := str(user["id"])
	var colors := _colors(uid)
	var node := Control.new()
	node.size = Vector2(76, 128)
	node.pivot_offset = Vector2(38, 106)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_meta("uid", uid)
	node.set_meta("shirt", Color(colors[1]))
	node.draw.connect(_draw_climber.bind(node))
	parent.add_child(node)
	var holder := Ui.avatar(node, Vector2(14, 18), 48, Color.WHITE, 3)
	_set_avatar(holder, user)
	var crown := _canvas(node, Vector2(20, 0), Vector2(36, 22), Callable())
	crown.draw.connect(_draw_crown.bind(crown))
	crown.visible = false
	var name := _name(user)
	var width := minf(100.0, Ui.font(700).get_string_size(name, LEFT, -1, 12).x + 18.0)
	var pill := Ui.panel(node, Color(0, 0, 0, 0.65), Vector2(38 - width / 2.0, 108), Vector2(width, 18), 9)
	Ui.label(pill, name, 12, Vector2(0, -2), width, Color.WHITE, 700, CENTER, 22)
	return {"node": node, "holder": holder, "crown": crown, "pill": pill, "shown": 0.0, "hop": 0.0,
			"slot": absi(hash(uid)) % SLOTS, "colors": colors}


# ---------------------------------------------------------------- effects

func _strike(fx: Dictionary) -> void:
	_shake = 0.45
	var top := _y(fx["to"]) - 70.0
	var bottom := _y(fx["from"])
	for i in 8:
		var size := randf_range(28, 46)
		var rock := _canvas(_fx, Vector2(randf_range(LEDGE_L, LEDGE_R - 50), top - 80), Vector2(size, size), Callable())
		rock.pivot_offset = Vector2(size, size) / 2.0
		rock.draw.connect(func():
			rock.draw_colored_polygon(_shape(ROCK, Vector2.ZERO, size / 40.0), Color("#8a7f74"))
			rock.draw_polyline(_shape(ROCK + [ROCK[0]], Vector2.ZERO, size / 40.0), Color("#4a423a"), 3))
		var t := create_tween()
		t.tween_interval(i * 0.06)
		t.tween_property(rock, "position:y", bottom + 20, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(rock, "rotation", randf_range(-4, 4), 0.55)
		t.tween_property(rock, "modulate:a", 0.0, 0.2)
		t.tween_callback(rock.queue_free)
	var fell: Array = fx["fell"]
	var saved: Array = fx["saved"]
	for f in fell:
		var uid := str(f["user"]["id"])
		if _climbers.has(uid):
			var node: Control = _climbers[uid]["node"]
			var tilt := node.create_tween()          # dies with the node if the camera moves on
			tilt.tween_property(node, "rotation", deg_to_rad(-24), 0.15)
			tilt.tween_interval(0.5)
			tilt.tween_property(node, "rotation", 0.0, 0.3)
			_float_text(node.position + Vector2(-10, 0), "-%d" % roundi(f["from"] - f["to"]), DANGER)
	if fell.is_empty() and saved.is_empty():
		_say("الصخور نزلت وما صابت حدا", MUTED, "rock")
	for s in saved.slice(0, 2):
		_say("الجناحين حموا %s من الصخرة" % _name(s["user"]), WINGS, "wings")
	if not fell.is_empty():
		var names: Array = fell.slice(0, 3).map(func(f): return _name(f["user"]))
		var more := " و%d كمان" % (fell.size() - 3) if fell.size() > 3 else ""
		_say("صخرة! نزل %s%s" % ["، ".join(names), more], DANGER, "rock")


func _float_text(pos: Vector2, text: String, color: Color) -> void:
	var l := Ui.label(_fx, text, 26, pos, 96, color, 900)
	l.text_direction = Control.TEXT_DIRECTION_LTR
	l.add_theme_color_override("font_outline_color", Color(0.25, 0, 0))
	l.add_theme_constant_override("outline_size", 8)
	var t := create_tween()
	t.tween_property(l, "position:y", pos.y - 60, 1.0)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.4)
	t.tween_callback(l.queue_free)


func _beam() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.82, 0.25, 0.65))
	grad.set_color(1, Color(1, 0.82, 0.25, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var beam := TextureRect.new()
	beam.texture = tex
	beam.position = Vector2(W / 2.0 - 110, 0)
	beam.size = Vector2(220, VIEW_H)
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(beam)
	var t := create_tween()
	t.tween_interval(1.4)
	t.tween_property(beam, "modulate:a", 0.0, 0.6)
	t.tween_callback(beam.queue_free)
	for i in 8:
		var arrow := _canvas(_fx, Vector2(randf_range(LEDGE_L, LEDGE_R - 30), VIEW_H - randf_range(60, 300)),
				Vector2(30, 34), Callable())
		arrow.draw.connect(func(): arrow.draw_colored_polygon(PackedVector2Array([Vector2(15, 0),
				Vector2(30, 16), Vector2(20, 16), Vector2(20, 34), Vector2(10, 34), Vector2(10, 16), Vector2(0, 16)]), GOLD))
		var a := create_tween()
		a.tween_interval(i * 0.08)
		a.tween_property(arrow, "position:y", arrow.position.y - 260, 1.1)
		a.parallel().tween_property(arrow, "modulate:a", 0.0, 0.6).set_delay(0.5)
		a.tween_callback(arrow.queue_free)


# ---------------------------------------------------------------- header, map, feed

func _refresh_leaders() -> void:
	var top := logic.ranking(3)
	for i in _leaders.size():
		var l: Dictionary = _leaders[i]
		var has: bool = i < top.size() and top[i]["floor"] > 0.0
		l["box"].modulate.a = 1.0 if has else 0.35
		if has:
			_set_avatar(l["holder"], top[i]["user"])
			Ui.restyle(l["holder"], Color(_colors(str(top[i]["user"]["id"]))[0]), Ui.MEDALS[i], 3)
			l["name"].text = _name(top[i]["user"])
			l["floor"].text = "طابق %d" % int(top[i]["floor"])
		else:
			l["name"].text = "—"
			l["floor"].text = ""


func _map_y(f: float) -> float:
	return MAP_TRACK.position.y + MAP_TRACK.size.y * (1.0 - f / logic.top_floor)


func _draw_map() -> void:
	var font := Ui.font(700)
	var seg := MAP_TRACK.size.y / ZONES.size()
	for i in ZONES.size():
		_map.draw_rect(Rect2(MAP_TRACK.position.x, MAP_TRACK.end.y - seg * (i + 1), MAP_TRACK.size.x, seg),
				Color(ZONES[i]["key"]))
	for f in range(0, int(logic.top_floor) + 1, 25):
		_map.draw_string(font, Vector2(4, _map_y(f) + 5), str(f), LEFT, -1, 11, Color("#aab4c3"))
	var fx := MAP_TRACK.position.x + 6
	_map.draw_line(Vector2(fx, MAP_TRACK.position.y - 18), Vector2(fx, MAP_TRACK.position.y), Color("#e2e8f0"), 2)
	_map.draw_colored_polygon(_shape(FLAG, Vector2(fx + 1, MAP_TRACK.position.y - 18), 0.55), GOLD)
	if not logic.hazard.is_empty():
		var y1 := _map_y(logic.hazard["to"])
		_map.draw_style_box(_box(Color(1, 0.36, 0.36, 0.6), 3),
				Rect2(4, y1, MAP_SIZE.x - 12, _map_y(logic.hazard["from"]) - y1))
	var cy1 := _map_y(minf(logic.top_floor, _cam + VIEW_H / FLOOR_PX))
	var cam_rect := Rect2(6, cy1, MAP_SIZE.x - 16, _map_y(maxf(_cam, 0.0)) - cy1)
	_map.draw_style_box(_box(Color(1, 1, 1, 0.08), 6), cam_rect)
	_map.draw_rect(cam_rect, Color.WHITE, false, 2)
	var ranked := logic.ranking()
	for i in range(ranked.size() - 1, -1, -1):        # leaders drawn last, on top
		var uid := str(ranked[i]["user"]["id"])
		var x := 22.0 + (absi(hash(uid)) % SLOTS) * 6.5
		var y := _map_y(ranked[i]["floor"])
		if i < 3 and ranked[i]["floor"] > 0.0:
			_map.draw_circle(Vector2(x, y), 7, Color.BLACK)
			_map.draw_circle(Vector2(x, y), 5.5, Ui.MEDALS[i])
		else:
			_map.draw_circle(Vector2(x, y), 3.5, WINGS if logic.wings.has(uid) else Color("#e2e8f0"))


## Small icons on a 24x24 grid, scaled to the control.
func _draw_icon(ci: Control, kind: String, color: Color) -> void:
	var k := ci.size.x / 24.0
	match kind:
		"heart":
			ci.draw_circle(Vector2(7.5, 8.5) * k, 5.2 * k, color)
			ci.draw_circle(Vector2(16.5, 8.5) * k, 5.2 * k, color)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(2.6, 10.5) * k, Vector2(21.4, 10.5) * k,
					Vector2(12, 21) * k]), color)
		"flag":
			ci.draw_line(Vector2(5, 22) * k, Vector2(5, 3) * k, color, 2.4 * k)
			ci.draw_colored_polygon(_shape(FLAG, Vector2(5, 4) * k, 0.55 * k), color)
		"wings":
			ci.draw_colored_polygon(_shape(WING, Vector2(0, 6) * k, 0.21 * k), color)
			ci.draw_colored_polygon(_shape(WING, Vector2(0, 6) * k, 0.21 * k, 112.0), color)
		"gift":
			ci.draw_rect(Rect2(Vector2(3, 9) * k, Vector2(18, 12) * k), color, false, 2.2 * k)
			ci.draw_line(Vector2(2, 9) * k, Vector2(22, 9) * k, color, 2.2 * k)
			ci.draw_line(Vector2(12, 9) * k, Vector2(12, 21) * k, color, 2.2 * k)
			ci.draw_arc(Vector2(9, 6) * k, 2.8 * k, 0, TAU, 12, color, 2 * k)
			ci.draw_arc(Vector2(15, 6) * k, 2.8 * k, 0, TAU, 12, color, 2 * k)
		"rocket":
			for part in [[Vector2(12, 2), Vector2(17, 8), Vector2(17, 16), Vector2(7, 16), Vector2(7, 8), Vector2(12, 2)],
					[Vector2(7, 12), Vector2(3, 16), Vector2(3, 19), Vector2(7, 17)],
					[Vector2(17, 12), Vector2(21, 16), Vector2(21, 19), Vector2(17, 17)],
					[Vector2(10, 20), Vector2(12, 23), Vector2(14, 20)]]:
				ci.draw_polyline(_shape(part, Vector2.ZERO, k), color, 2.2 * k)
		"rock":
			ci.draw_colored_polygon(_shape(ROCK, Vector2(2, 2) * k, 0.5 * k), color)
		"crown":
			ci.draw_colored_polygon(_shape(CROWN, Vector2(3, 5) * k, 0.53 * k), color)
		"clock":
			ci.draw_arc(Vector2(12, 13) * k, 8 * k, 0, TAU, 24, color, 2.4 * k)
			ci.draw_polyline(_shape([Vector2(12, 9), Vector2(12, 13), Vector2(15, 15)], Vector2.ZERO, k), color, 2.4 * k)
			ci.draw_line(Vector2(9, 2) * k, Vector2(15, 2) * k, color, 2.4 * k)
		"warn":
			ci.draw_polyline(_shape([Vector2(12, 3), Vector2(22, 20), Vector2(2, 20), Vector2(12, 3)], Vector2.ZERO, k),
					color, 2.4 * k)
			ci.draw_line(Vector2(12, 10) * k, Vector2(12, 14) * k, color, 2.4 * k)
			ci.draw_circle(Vector2(12, 17.3) * k, 1.3 * k, color)
		"mountain":
			ci.draw_colored_polygon(_shape([Vector2(1, 22), Vector2(9, 8), Vector2(13, 14), Vector2(16.5, 6),
					Vector2(23, 22)], Vector2.ZERO, k), color)


func _icon(parent: Control, kind: String, pos: Vector2, size: float, color: Color) -> Control:
	var ci := _canvas(parent, pos, Vector2(size, size), Callable())
	ci.draw.connect(_draw_icon.bind(ci, kind, color))
	return ci


func _say(text: String, color: Color, icon: String) -> void:
	var line := Control.new()
	line.custom_minimum_size = Vector2(W - 40, 36)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon(line, icon, Vector2(W - 64, 7), 22, color)
	Ui.label(line, text, 20, Vector2(0, 0), W - 76, color, 700, RIGHT, 36)
	_feed.add_child(line)
	while _feed.get_child_count() > FEED_LINES:
		var first := _feed.get_child(0)
		_feed.remove_child(first)
		first.queue_free()


func _show_popup(text: String) -> void:
	_popup_text.text = text
	_popup.visible = true
	_popup.scale = Vector2(0.4, 0.4)
	_popup.modulate.a = 1.0
	if _popup_tween:
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.tween_property(_popup, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tween.tween_interval(2.4)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.4)
	_popup_tween.tween_callback(func(): _popup.visible = false)


# ---------------------------------------------------------------- result

static func _wins_text(n: int) -> String:
	if n == 1:
		return "فاز مرة"
	if n == 2:
		return "فاز مرتين"
	if n <= 10:
		return "فاز %d مرات" % n
	return "فاز %d مرة" % n


static func _gifts_text(n: int) -> String:
	if n == 1:
		return "هدية"
	if n == 2:
		return "هديتين"
	if n <= 10:
		return "%d هدايا" % n
	return "%d هدية" % n


func _show_result(fx: Dictionary) -> void:
	var winner: Dictionary = fx["winner"]
	_result.visible = true
	_popup.visible = false
	_caption.visible = false
	_res_round.text = "الجولة %d خلصت" % logic.round_no
	_res_stage.visible = not winner.is_empty()
	if winner.is_empty():
		_res_title.text = "ما حدا تسلّق هالجولة"
		_res_name.text = "اعمل لايك وابدأ التسلّق!"
		_res_stats.text = ""
	else:
		var user: Dictionary = winner["user"]
		var uid := str(user["id"])
		_res_title.text = "وصل للقمة!" if winner["top"] else "خلص الوقت!"
		_res_platform.text = "القمة · 100" if winner["top"] else "طابق %d" % int(winner["floor"])
		var node: Control = _res_climber["node"]
		node.set_meta("uid", uid)
		node.set_meta("shirt", Color(_colors(uid)[1]))
		node.queue_redraw()
		Ui.restyle(_res_climber["holder"], Color(_colors(uid)[0]), GOLD, 3)
		_set_avatar(_res_climber["holder"], user)
		_res_name.text = _name(user)
		var parts: PackedStringArray = []
		if winner["top"]:
			var s := int(winner["seconds"])
			parts.append("وصل بـ %d:%02d دقيقة" % [s / 60, s % 60])
		else:
			parts.append("الأعلى على البرج")
		parts.append("%d لايك" % winner["likes"])
		if winner["gifts"] > 0:
			parts.append(_gifts_text(winner["gifts"]))
		_res_stats.text = " · ".join(parts)
	var top: Array = fx["top"]
	for i in _res_rows.size():
		var row: Dictionary = _res_rows[i]
		var has := i + 1 < top.size()
		row["box"].visible = has
		if has:
			var e: Dictionary = top[i + 1]
			_set_avatar(row["holder"], e["user"])
			Ui.restyle(row["holder"], Color(_colors(str(e["user"]["id"]))[0]), Color.WHITE, 2)
			row["name"].text = _name(e["user"])
			row["floor"].text = "طابق %d" % int(e["floor"])
			var frac := clampf(e["floor"] / logic.top_floor, 0.0, 1.0)
			var track: ColorRect = row["track"]
			row["fill"].size.x = track.size.x * frac
			row["fill"].position.x = track.size.x * (1.0 - frac)     # grows from the right
			row["fill"].color = Color(ZONES[_zone(e["floor"])]["key"])
	var hall: Array = fx["hall"]
	for i in _hall.size():
		var card: Dictionary = _hall[i]
		var has := i < hall.size()
		card["box"].visible = has
		if has:
			_set_avatar(card["holder"], hall[i]["user"])
			Ui.restyle(card["holder"], Color(_colors(str(hall[i]["user"]["id"]))[0]), Ui.MEDALS[i], 3)
			card["name"].text = _name(hall[i]["user"])
			card["wins"].text = _wins_text(hall[i]["wins"])
	for piece in _confetti:
		piece.position = Vector2(randf_range(10, W - 20), randf_range(-420, 160))
		var t := create_tween()
		t.tween_property(piece, "position:y", piece.position.y + randf_range(500, 700), randf_range(3.0, 5.0))
		t.parallel().tween_property(piece, "rotation", randf_range(-6, 6), 4.0)


# ---------------------------------------------------------------- building

## A plain Control that draws with `drawer` (or gets one connected later).
func _canvas(parent: Node, pos: Vector2, size: Vector2, drawer: Callable) -> Control:
	var c := Control.new()
	c.position = pos
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if drawer.is_valid():
		c.draw.connect(drawer)
	parent.add_child(c)
	return c


func _build_world() -> void:
	_world = Control.new()
	_world.position = Vector2(0, VIEW_Y)
	_world.size = Vector2(W, VIEW_H)
	_world.clip_contents = true
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_world)
	_tower = _canvas(_world, Vector2.ZERO, _world.size, _draw_tower)
	_band = _canvas(_world, Vector2(LEDGE_L, 0), Vector2(LEDGE_R - LEDGE_L, 100), _draw_band)
	_band.visible = false
	_marks = _canvas(_world, Vector2.ZERO, _world.size, _draw_marks)
	_fx = _canvas(_world, Vector2.ZERO, _world.size, Callable())
	_band_pill = Ui.panel(_world, Color("#5a1414"), Vector2(250, 0), Vector2(340, 44), 22, DANGER, 2)
	_icon(_band_pill, "warn", Vector2(290, 11), 22, Color("#ffd0d0"))
	_band_text = Ui.label(_band_pill, "", 20, Vector2(14, 0), 270, Color("#ffd0d0"), 800, CENTER, 44)
	_band_pill.visible = false
	_caption = Ui.panel(_ui, Color(0.02, 0.03, 0.08, 0.78), Vector2(140, VIEW_Y + 8), Vector2(330, 38), 19, GOLD, 2)
	_caption_text = Ui.label(_caption, "", 17, Vector2(10, 0), 310, Color.WHITE, 800, CENTER, 38)
	_caption.visible = false
	_zone_badge = Ui.panel(_ui, Color(0.02, 0.03, 0.08, 0.72), Vector2(W - 210, VIEW_Y + 10), Vector2(190, 34), 17)
	_zone_dot = Ui.rect(_zone_badge, Color.WHITE, Vector2(164, 11), Vector2(12, 12))
	_zone_text = Ui.label(_zone_badge, "", 16, Vector2(10, 0), 146, Color("#d7dee6"), 800, RIGHT, 34)


func _build_map() -> void:
	Ui.panel(_ui, Color(0.02, 0.04, 0.09, 0.72), MAP_POS, MAP_SIZE, 16, Color(1, 1, 1, 0.22), 2)
	Ui.label(_ui, "الخريطة", 14, MAP_POS, MAP_SIZE.x, Color("#cfd8e3"), 800, CENTER, 26)
	_map = _canvas(_ui, MAP_POS, MAP_SIZE, _draw_map)


func _build_header() -> void:
	var head := _canvas(_ui, Vector2.ZERO, Vector2(W, VIEW_Y), Callable())
	head.draw.connect(func(): head.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(W, 0), Vector2(W, VIEW_Y),
			Vector2(0, VIEW_Y)]), PackedColorArray([Color(0.02, 0.03, 0.08, 0.92), Color(0.02, 0.03, 0.08, 0.92),
			Color(0.02, 0.03, 0.08, 0.55), Color(0.02, 0.03, 0.08, 0.55)])))
	_icon(_ui, "mountain", Vector2(470, 12), 32, GOLD)
	Ui.label(_ui, "تسلّق البرج", 34, Vector2(210, 0), 256, GOLD, 900, CENTER, 56)
	_status = Ui.label(_ui, "", 11, Vector2(W - 120, -2), 112, Color.WHITE, 500, RIGHT, 16)
	_count = Ui.label(_ui, "0 متسلّق", 17, Vector2(W - 170, 14), 156, Color("#cfd8e3"), 700, RIGHT, 32)
	var pill := Ui.panel(_ui, Color(1, 1, 1, 0.1), Vector2(14, 10), Vector2(106, 36), 18)
	_icon(pill, "clock", Vector2(12, 8), 20, Color.WHITE)
	_timer = Ui.label(pill, "", 21, Vector2(36, 0), 62, Color.WHITE, 800, LEFT, 36)
	_timer.text_direction = Control.TEXT_DIRECTION_LTR

	# What each interaction does, at the top: TikTok's comments cover the bottom of the stream.
	Ui.panel(_ui, Color(0.02, 0.03, 0.08, 0.9), Vector2(6, 56), Vector2(W - 12, 92), 18, Color(1, 1, 1, 0.14), 1)
	var col_w := (W - 16) / HELP.size()
	for i in HELP.size():
		var h: Array = HELP[i]
		var x := W - 8 - col_w * (i + 1)             # first item on the right
		var color := Color(h[3])
		var box := Ui.panel(_ui, Color(color, 0.18), Vector2(x + col_w / 2 - 21, 61), Vector2(42, 42), 14)
		_icon(box, h[2], Vector2(9, 9), 24, color)
		Ui.label(_ui, h[0], 16, Vector2(x - 4, 101), col_w + 8, Color.WHITE, 900, CENTER, 24)
		Ui.label(_ui, h[1], 15, Vector2(x - 4, 122), col_w + 8, color.lightened(0.25), 700, CENTER, 22)

	for i in 3:
		var x := W - 12.0 - 232.0 * (i + 1) + 8.0     # first place on the right
		var box := Ui.panel(_ui, Color(0.02, 0.03, 0.08, 0.6), Vector2(x, 153), Vector2(224, 48), 24, Ui.MEDALS[i], 2)
		var badge := Ui.panel(box, Ui.MEDALS[i], Vector2(8, 11), Vector2(26, 26), 13)
		Ui.label(badge, str(i + 1), 15, Vector2.ZERO, 26, Color("#1a1300"), 900, CENTER, 26)
		var holder := Ui.avatar(box, Vector2(178, 5), 38, Ui.MEDALS[i], 3)
		var nm := Ui.label(box, "", 16, Vector2(40, 1), 132, Color.WHITE, 800, RIGHT, 24)
		var fl := Ui.label(box, "", 13, Vector2(40, 23), 132, Ui.MEDALS[i], 700, RIGHT, 22)
		_leaders.append({"box": box, "holder": holder, "name": nm, "floor": fl})


func _build_bottom() -> void:
	_feed = VBoxContainer.new()
	_feed.position = Vector2(20, H - 100)
	_feed.size = Vector2(W - 40, 96)
	_feed.add_theme_constant_override("separation", 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_feed)
	_popup = Ui.panel(_ui, Color("#3b1d4a"), Vector2(80, 280), Vector2(560, 150), 24, GOLD, 4)
	_popup.pivot_offset = Vector2(280, 75)
	_popup_text = Ui.paragraph(_popup, "", 30, Vector2(14, 6), Vector2(532, 138), GOLD, 800)
	_popup.visible = false


func _build_result() -> void:
	_result = Ui.layer(_ui)
	var bg := _canvas(_result, Vector2.ZERO, Vector2(W, H), Callable())
	bg.draw.connect(func():
		bg.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(W, 0), Vector2(W, 400), Vector2(0, 400)]),
				PackedColorArray([Color("#120624"), Color("#120624"), Color("#2e1a5c"), Color("#2e1a5c")]))
		bg.draw_polygon(PackedVector2Array([Vector2(0, 400), Vector2(W, 400), Vector2(W, H), Vector2(0, H)]),
				PackedColorArray([Color("#2e1a5c"), Color("#2e1a5c"), Color("#1a0f38"), Color("#1a0f38")]))
		for i in 40:
			bg.draw_circle(Vector2(fmod(i * 97.0, W), fmod(i * 61.0, H)), 1.0 + i % 3 * 0.6,
					Color(1, 1, 1, 0.2 + (i % 5) * 0.12)))
	var colors := [GOLD, WINGS, LIKE, Ui.PURPLE, Ui.BLUE]
	for i in 30:
		var piece := Ui.rect(_result, colors[i % colors.size()], Vector2(-50, -50), Vector2(9, 16))
		piece.pivot_offset = Vector2(4.5, 8)
		_confetti.append(piece)
	_res_round = Ui.label(_result, "", 18, Vector2(0, 6), W, Color("#b9b3ff"), 800, CENTER, 30)
	_res_title = Ui.label(_result, "", 44, Vector2(0, 28), W, GOLD, 900, CENTER, 66)

	_res_stage = Ui.layer(_result)
	var glow := GradientTexture2D.new()
	glow.gradient = Gradient.new()
	glow.gradient.set_color(0, Color(1, 0.82, 0.25, 0.35))
	glow.gradient.set_color(1, Color(1, 0.82, 0.25, 0.0))
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	var halo := TextureRect.new()
	halo.texture = glow
	halo.position = Vector2(180, 96)
	halo.size = Vector2(360, 220)
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_res_stage.add_child(halo)
	var flag := _canvas(_res_stage, Vector2(470, 96), Vector2(110, 200), Callable())
	flag.draw.connect(func():
		flag.draw_style_box(_box(Color("#e2e8f0"), 3), Rect2(0, 0, 6, 200))
		flag.draw_colored_polygon(_shape(FLAG, Vector2(6, 4), 3.2), GOLD)
		flag.draw_colored_polygon(_shape(STAR, Vector2(22, 14), 1.6), Color("#7a5a00")))
	Ui.rect(_res_stage, Color("#ffe68a"), Vector2(170, 292), Vector2(380, 10))
	var plat := Ui.rect(_res_stage, Color("#c79a10"), Vector2(170, 302), Vector2(380, 24))
	_res_platform = Ui.label(plat, "", 14, Vector2.ZERO, 380, Color("#3a2a00"), 900, CENTER, 24)
	_res_climber = _make_climber(_res_stage, {"id": "", "name": ""})
	var champ: Control = _res_climber["node"]
	champ.set_meta("cheer", true)
	champ.position = Vector2(328, 202)
	champ.scale = Vector2(1.8, 1.8)
	_res_climber["pill"].visible = false
	_res_climber["crown"].visible = true

	_res_name = Ui.label(_result, "", 34, Vector2(0, 326), W, Color.WHITE, 900, CENTER, 46)
	_res_stats = Ui.label(_result, "", 17, Vector2(0, 370), W, Color("#cfc9ff"), 700, CENTER, 28)

	# Round order on the right, the stream's champions on the left.
	Ui.label(_result, "ترتيب الجولة", 19, Vector2(372, 404), 336, GOLD, 900, RIGHT, 32)
	for i in 4:
		var box := Ui.panel(_result, Color(1, 1, 1, 0.07), Vector2(372, 440 + i * 50), Vector2(336, 44), 14)
		Ui.label(box, str(i + 2), 17, Vector2(306, 0), 26, Color("#cfc9ff"), 900, CENTER, 44)
		var holder := Ui.avatar(box, Vector2(270, 6), 32, Color.WHITE, 2)
		var nm := Ui.label(box, "", 16, Vector2(150, 0), 114, Color.WHITE, 800, RIGHT, 44)
		var track := Ui.rect(box, Color(1, 1, 1, 0.12), Vector2(72, 18), Vector2(72, 8))
		var fill := Ui.rect(track, Color.WHITE, Vector2.ZERO, Vector2(0, 8))
		var fl := Ui.label(box, "", 14, Vector2(8, 0), 62, Color("#cfc9ff"), 800, LEFT, 44)
		_res_rows.append({"box": box, "holder": holder, "name": nm, "track": track, "fill": fill, "floor": fl})

	Ui.label(_result, "لوحة الأبطال · البث كله", 19, Vector2(12, 404), 336, GOLD, 900, RIGHT, 32)
	for i in 3:
		var box := Ui.panel(_result, Color(1, 1, 1, 0.06), Vector2(12, 440 + i * 50), Vector2(336, 44), 14, Ui.MEDALS[i], 2)
		var holder := Ui.avatar(box, Vector2(292, 6), 32, Ui.MEDALS[i], 3)
		var nm := Ui.label(box, "", 16, Vector2(128, 0), 158, Color.WHITE, 800, RIGHT, 44)
		var wins := Ui.label(box, "", 14, Vector2(10, 0), 116, Ui.MEDALS[i], 800, LEFT, 44)
		_hall.append({"box": box, "holder": holder, "name": nm, "wins": wins})

	var clock := Ui.panel(_result, Color(1, 1, 1, 0.1), Vector2(12, H - 54), Vector2(336, 42), 21)
	_icon(clock, "clock", Vector2(296, 11), 20, Color("#e2e0ff"))
	_res_clock = Ui.label(clock, "", 18, Vector2(12, 0), 276, Color("#e2e0ff"), 800, CENTER, 42)
	_result.visible = false
