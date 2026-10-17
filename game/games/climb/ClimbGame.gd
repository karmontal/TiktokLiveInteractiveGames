extends Node2D
## Tower climb screen (720x1280). Rules live in ClimbLogic.gd; this file only draws.
## The camera follows the highest climber; the minimap on the left shows the whole tower,
## every climber as a dot, the part the camera shows, and where the rocks will fall.

const ClimbLogic := preload("res://games/climb/ClimbLogic.gd")
const Ui := preload("res://core/Ui.gd")

const W := 720.0
const LEFT := HORIZONTAL_ALIGNMENT_LEFT
const RIGHT := HORIZONTAL_ALIGNMENT_RIGHT
const VIEW_Y := 150.0            # the world view, between the header and the feed
const VIEW_H := 890.0
const FLOOR_PX := 100.0
const LEADER_AT := 6.0           # floors between the bottom of the view and the leader
const TOWER_L := 112.0
const TOWER_R := 708.0
const SLOTS := 8                 # climbers spread over 8 spots per floor
const AVATAR := 52.0
const MAX_SHOWN := 30            # climber avatars drawn at once (the minimap shows everyone)
const MAP_POS := Vector2(12, 176)
const MAP_SIZE := Vector2(88, 560)
const MAP_PAD := 14.0
const FEED_LINES := 3
const SKY_LOW := Color("#0f1b3d")
const SKY_HIGH := Color("#1a0b2e")
const WINGS := Color("#5eead4")

var logic := ClimbLogic.new()

var _ui: Control
var _sky: ColorRect
var _world: Control
var _ground: ColorRect
var _ledges: Array[Dictionary] = []      # pool: {"rect", "label"}
var _climbers := {}                      # uid -> {"node", "holder", "shown", "slot"}
var _shown_ids: Array = []
var _refresh_left := 0.0
var _cam := 0.0
var _band: ColorRect
var _band_label: Label
var _blink := 0.0
var _map: Control
var _leaders: Array[Dictionary] = []     # header chips: {"box", "holder", "name", "floor"}
var _timer: Label
var _count: Label
var _feed: VBoxContainer
var _popup: Panel
var _popup_text: Label
var _popup_tween: Tween
var _shake := 0.0
var _result: Control
var _res_title: Label
var _res_avatar: Panel
var _res_name: Label
var _res_floor: Label
var _res_rows: Array[Label] = []
var _hall_rows: Array[Label] = []
var _res_clock: Label
var _status: Label
var _users := {}                         # uid -> user, for avatars that load later


func _ready() -> void:
	Music.play("climb_adventure")
	_ui = Ui.root(self)
	_sky = Ui.rect(_ui, SKY_LOW, Vector2.ZERO, Vector2(W, Ui.H))
	_build_world()
	_build_header()
	_build_map()
	_build_bottom()
	_build_result()
	EventBus.event_received.connect(_on_event)
	EventBus.connection_changed.connect(_on_connection)
	AvatarCache.avatar_ready.connect(_on_avatar)
	_on_connection(EventBus.connected)
	_apply(logic.start())


func _process(delta: float) -> void:
	_apply(logic.tick(delta))
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		_refresh_shown()
		_refresh_leaders()
		_map.queue_redraw()

	var target := clampf(logic.leader_floor() - LEADER_AT, 0.0, logic.top_floor - VIEW_H / FLOOR_PX + 0.6)
	_cam = lerpf(_cam, target, minf(1.0, delta * 3.0))
	_sky.color = SKY_LOW.lerp(SKY_HIGH, _cam / logic.top_floor)
	_place_ledges()
	for uid in _shown_ids:
		var c: Dictionary = _climbers[uid]
		c["shown"] = lerpf(c["shown"], logic.floor_of.get(uid, 0.0), minf(1.0, delta * 5.0))
		c["node"].position = Vector2(_slot_x(c["slot"]), _y(c["shown"]) - AVATAR - 22)

	_band.visible = not logic.hazard.is_empty()
	if _band.visible:
		_blink += delta
		_band.position.y = _y(logic.hazard["to"]) - 30
		_band.size.y = (logic.hazard["to"] - logic.hazard["from"]) * FLOOR_PX + 30
		_band.color = Color(1, 0.2, 0.2, 0.18 + 0.12 * sin(_blink * 10.0))
		_band_label.text = "انتبه! صخور نازلة بعد %d" % ceili(logic.hazard["in"])

	var secs := maxi(0, ceili(logic.time_left))
	_timer.text = "%d:%02d" % [secs / 60, secs % 60] if logic.phase == "climb" else ""
	if logic.phase == "result":
		_res_clock.text = "جولة جديدة بعد %d" % secs

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
				for uid in _climbers:
					_climbers[uid]["shown"] = 0.0
				_say("الجولة %d بلّشت! أول واحد بيوصل للقمة بيفوز" % fx["round"], Ui.ACCENT)
			"joined":
				_users[str(fx["user"]["id"])] = fx["user"]
			"climb":
				_hop(str(fx["user"]["id"]))
			"checkpoint":
				_say("%s عمل فولو: نقطة حفظ على طابق %d" % [_name(fx["user"]), fx["floor"]], Ui.GOOD)
			"wings":
				_say("%s عمل شير: جناحين بيحموه من الصخرة الجاية" % _name(fx["user"]), WINGS)
			"gift":
				var gift: Dictionary = fx["gift"]
				_say("هدية من %s: طلع %d طوابق" % [_name(fx["user"]), fx["floors"]], Ui.PURPLE)
				if gift.get("tier", "small") != "small":
					_show_popup("%s\n%s ×%d" % [_name(fx["user"]), gift.get("name", ""), fx["count"]])
			"lift_all":
				_show_popup("%s رفع الكل!\n+%d طوابق لكل المتسلقين" % [_name(fx["user"]), fx["floors"]])
				_shake = 0.6
			"hazard_warning":
				_blink = 0.0
			"hazard_strike":
				_strike(fx)
			"summit":
				_say("%s وصل للقمة!" % _name(fx["user"]), Ui.ACCENT)
			"round_end":
				_show_result(fx)
	_count.text = "%d متسلق" % logic.floor_of.size()


func _on_connection(connected: bool) -> void:
	_status.text = "● متصل" if connected else "● غير متصل"
	_status.add_theme_color_override("font_color", Ui.GOOD if connected else Color("#ff5c5c"))


func _on_avatar(user_id: String, texture: Texture2D) -> void:
	var holders: Array = _leaders.map(func(l): return l["holder"])
	holders.append(_res_avatar)
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


# ---------------------------------------------------------------- world

## y inside the world view of a climber standing on floor f.
func _y(f: float) -> float:
	return VIEW_H - 40.0 - (f - _cam) * FLOOR_PX


func _slot_x(slot: int) -> float:
	return TOWER_L + 18.0 + slot * (TOWER_R - TOWER_L - 110.0 - AVATAR) / (SLOTS - 1)


func _place_ledges() -> void:
	var first := int(floor(_cam)) - 1
	for i in _ledges.size():
		var fl := first + i
		var l: Dictionary = _ledges[i]
		var shown := fl >= 0 and fl <= int(logic.top_floor)
		l["rect"].visible = shown
		l["label"].visible = shown
		if not shown:
			continue
		var y := _y(fl)
		var summit := fl == int(logic.top_floor)
		var milestone := fl % 10 == 0
		l["rect"].position.y = y
		l["rect"].color = Ui.ACCENT if summit else (Color("#8b7cf6") if milestone else Color("#3a3470"))
		l["label"].position.y = y - 34
		l["label"].text = "القمة" if summit else str(fl)
		l["label"].add_theme_color_override("font_color", Ui.ACCENT if summit or milestone else Ui.MUTED)
	_ground.position.y = _y(0) + 10


## Which climbers get an avatar: the highest ones inside the view, up to MAX_SHOWN.
func _refresh_shown() -> void:
	var lo := _cam - 1.0
	var hi := _cam + VIEW_H / FLOOR_PX + 1.0
	var keep := {}
	for entry in logic.ranking():
		if keep.size() >= MAX_SHOWN:
			break
		if entry["floor"] >= lo and entry["floor"] <= hi:
			keep[str(entry["user"]["id"])] = entry
	for uid in _climbers.keys():
		if not keep.has(uid):
			_climbers[uid]["node"].queue_free()
			_climbers.erase(uid)
	var rank := 0
	for uid in keep:
		if not _climbers.has(uid):
			_climbers[uid] = _make_climber(keep[uid]["user"], keep[uid]["floor"])
		var ring := Color.WHITE
		if rank == 0 and logic.leader_floor() > 0.0 and keep[uid]["floor"] == logic.leader_floor():
			ring = Ui.ACCENT
		elif logic.wings.has(uid):
			ring = WINGS
		Ui.restyle(_climbers[uid]["holder"], Ui.AVATAR_BG, ring, 2 if ring == Color.WHITE else 4)
		rank += 1
	_shown_ids = keep.keys()


func _make_climber(user: Dictionary, f: float) -> Dictionary:
	var uid := str(user["id"])
	var node := Control.new()
	node.size = Vector2(AVATAR + 40, AVATAR + 24)
	node.pivot_offset = Vector2(node.size.x / 2, node.size.y)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(node)
	var holder := Ui.avatar(node, Vector2(20, 0), AVATAR, Color.WHITE, 2)
	_set_avatar(holder, user)
	var nm := Ui.label(node, _name(user), 14, Vector2(0, AVATAR - 2), AVATAR + 40, Color.WHITE, 700)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	nm.add_theme_constant_override("outline_size", 5)
	return {"node": node, "holder": holder, "shown": f, "slot": absi(hash(uid)) % SLOTS}


func _hop(uid: String) -> void:
	if not _climbers.has(uid):
		return
	var node: Control = _climbers[uid]["node"]
	node.scale = Vector2(0.85, 1.2)
	create_tween().tween_property(node, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _strike(fx: Dictionary) -> void:
	_shake = 0.45
	var top := _y(fx["to"]) - 30
	var bottom := _y(fx["from"])
	for i in 7:
		var rock := Ui.panel(_world, Color("#8a8178"), Vector2(randf_range(TOWER_L + 10, TOWER_R - 60), top - 60),
				Vector2(34, 30), 12, Color("#4a443d"), 3)
		var t := create_tween()
		t.tween_interval(i * 0.06)
		t.tween_property(rock, "position:y", bottom + 20, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(rock, "rotation", randf_range(-3, 3), 0.55)
		t.tween_property(rock, "modulate:a", 0.0, 0.2)
		t.tween_callback(rock.queue_free)
	var fell: Array = fx["fell"]
	var saved: Array = fx["saved"]
	if fell.is_empty() and saved.is_empty():
		_say("الصخور نزلت وما صابت حدا", Ui.MUTED)
	for s in saved.slice(0, 2):
		_say("الجناحين حموا %s من الصخرة" % _name(s["user"]), WINGS)
	if not fell.is_empty():
		var names: Array = fell.slice(0, 3).map(func(f): return _name(f["user"]))
		var more := " و%d كمان" % (fell.size() - 3) if fell.size() > 3 else ""
		_say("صخرة! نزل %s%s" % ["، ".join(names), more], Color("#ff8a8a"))


# ---------------------------------------------------------------- header, map, feed

func _refresh_leaders() -> void:
	var top := logic.ranking(3)
	for i in _leaders.size():
		var l: Dictionary = _leaders[i]
		var has: bool = i < top.size() and top[i]["floor"] > 0.0
		l["box"].visible = has
		if has:
			_set_avatar(l["holder"], top[i]["user"])
			l["name"].text = _name(top[i]["user"])
			l["floor"].text = "طابق %d" % int(top[i]["floor"])


func _map_y(f: float) -> float:
	return MAP_PAD + (MAP_SIZE.y - MAP_PAD * 2) * (1.0 - f / logic.top_floor)


func _draw_map() -> void:
	var mid := MAP_SIZE.x / 2
	var font := Ui.font(700)
	_map.draw_rect(Rect2(mid - 5, MAP_PAD, 10, MAP_SIZE.y - MAP_PAD * 2), Color(1, 1, 1, 0.12))
	for f in range(0, int(logic.top_floor) + 1, 25):
		var y := _map_y(f)
		_map.draw_line(Vector2(mid - 9, y), Vector2(mid + 9, y), Color(1, 1, 1, 0.3), 2)
		_map.draw_string(font, Vector2(3, y + 5), str(f), LEFT, -1, 13, Ui.MUTED)
	_map.draw_colored_polygon(PackedVector2Array([Vector2(mid, MAP_PAD - 12),
			Vector2(mid + 16, MAP_PAD - 6), Vector2(mid, MAP_PAD)]), Ui.ACCENT)   # flag at the top
	if not logic.hazard.is_empty():
		var y1 := _map_y(logic.hazard["to"])
		_map.draw_rect(Rect2(4, y1, MAP_SIZE.x - 8, _map_y(logic.hazard["from"]) - y1), Color(1, 0.25, 0.25, 0.45))
	var cy1 := _map_y(minf(logic.top_floor, _cam + VIEW_H / FLOOR_PX))
	_map.draw_rect(Rect2(3, cy1, MAP_SIZE.x - 6, _map_y(_cam) - cy1), Color(1, 1, 1, 0.7), false, 2)
	var ranked := logic.ranking()
	for i in range(ranked.size() - 1, -1, -1):        # leaders drawn last, on top
		var uid := str(ranked[i]["user"]["id"])
		var x := 24.0 + (absi(hash(uid)) % SLOTS) * (MAP_SIZE.x - 40.0) / (SLOTS - 1)
		var y := _map_y(ranked[i]["floor"])
		if i < 3 and ranked[i]["floor"] > 0.0:
			_map.draw_circle(Vector2(x, y), 7, Color.BLACK)
			_map.draw_circle(Vector2(x, y), 5.5, Ui.MEDALS[i])
		else:
			_map.draw_circle(Vector2(x, y), 3.5, WINGS if logic.wings.has(uid) else Color(1, 1, 1, 0.85))


func _say(text: String, color: Color) -> void:
	var line := Ui.label(_feed, text, 22, Vector2.ZERO, W - 40, color, 600)
	line.custom_minimum_size = Vector2(W - 40, 36)
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


func _show_result(fx: Dictionary) -> void:
	var winner: Dictionary = fx["winner"]
	_result.visible = true
	_popup.visible = false
	_res_avatar.visible = not winner.is_empty()
	if winner.is_empty():
		_res_title.text = "ما حدا تسلّق هالجولة"
		_res_name.text = "اعمل لايك وابدأ التسلق!"
		_res_floor.text = ""
	else:
		_res_title.text = "وصل للقمة!" if winner["top"] else "خلص الوقت! الأعلى بيفوز"
		_set_avatar(_res_avatar, winner["user"])
		_res_name.text = _name(winner["user"])
		_res_floor.text = "طابق %d" % int(winner["floor"])
	var top: Array = fx["top"]
	for i in _res_rows.size():
		_res_rows[i].text = ""
		if i + 1 < top.size():
			_res_rows[i].text = "المركز %d: %s · طابق %d" % [i + 2, _name(top[i + 1]["user"]), int(top[i + 1]["floor"])]
	var hall: Array = fx["hall"]
	for i in _hall_rows.size():
		_hall_rows[i].text = ""
		if i < hall.size():
			_hall_rows[i].text = "فاز %d مرة: %s" % [hall[i]["wins"], _name(hall[i]["user"])]


# ---------------------------------------------------------------- building

func _build_world() -> void:
	_world = Control.new()
	_world.position = Vector2(0, VIEW_Y)
	_world.size = Vector2(W, VIEW_H)
	_world.clip_contents = true
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_world)
	Ui.rect(_world, Color(1, 1, 1, 0.04), Vector2(TOWER_L, 0), Vector2(TOWER_R - TOWER_L, VIEW_H))
	Ui.rect(_world, Color(1, 1, 1, 0.10), Vector2(TOWER_L, 0), Vector2(6, VIEW_H))
	Ui.rect(_world, Color(1, 1, 1, 0.10), Vector2(TOWER_R - 6, 0), Vector2(6, VIEW_H))
	_ground = Ui.rect(_world, Color("#1f5134"), Vector2(0, VIEW_H), Vector2(W, VIEW_H))
	for i in int(VIEW_H / FLOOR_PX) + 3:
		var rect := Ui.rect(_world, Color.WHITE, Vector2(TOWER_L + 6, 0), Vector2(TOWER_R - TOWER_L - 12, 10))
		var label := Ui.label(_world, "", 22, Vector2(TOWER_R - 96, 0), 84, Ui.MUTED, 800, RIGHT, 32)
		_ledges.append({"rect": rect, "label": label})
	_band = Ui.rect(_world, Color(1, 0.2, 0.2, 0.25), Vector2(TOWER_L, 0), Vector2(TOWER_R - TOWER_L, 100))
	_band_label = Ui.label(_band, "", 26, Vector2.ZERO, TOWER_R - TOWER_L, Color("#ffd0d0"), 800)
	_band_label.add_theme_color_override("font_outline_color", Color(0.3, 0, 0))
	_band_label.add_theme_constant_override("outline_size", 8)
	_band.visible = false


func _build_header() -> void:
	Ui.rect(_ui, Color(0, 0, 0, 0.45), Vector2.ZERO, Vector2(W, VIEW_Y))
	Ui.label(_ui, "تسلّق البرج", 44, Vector2(0, 2), W, Ui.ACCENT, 800, HORIZONTAL_ALIGNMENT_CENTER, 70)
	_status = Ui.label(_ui, "", 15, Vector2(8, 0), 120, Color.WHITE, 500, LEFT, 24)
	_timer = Ui.label(_ui, "", 30, Vector2(14, 22), 120, Color.WHITE, 800, LEFT, 46)
	_count = Ui.label(_ui, "0 متسلق", 22, Vector2(W - 174, 22), 160, Ui.MUTED, 600, RIGHT, 46)
	for i in 3:
		var x := W - 236.0 * (i + 1)                 # first place on the right
		var box := Ui.panel(_ui, Color(1, 1, 1, 0.07), Vector2(x + 6, 76), Vector2(224, 64), 32,
				Ui.MEDALS[i], 2)
		var holder := Ui.avatar(box, Vector2(166, 6), 52, Ui.MEDALS[i], 3)
		var nm := Ui.label(box, "", 18, Vector2(12, 4), 150, Color.WHITE, 700, RIGHT, 30)
		var fl := Ui.label(box, "", 16, Vector2(12, 30), 150, Ui.MEDALS[i], 600, RIGHT, 28)
		box.visible = false
		_leaders.append({"box": box, "holder": holder, "name": nm, "floor": fl})


func _build_map() -> void:
	Ui.panel(_ui, Color(0, 0, 0, 0.55), MAP_POS - Vector2(0, 26), MAP_SIZE + Vector2(0, 26), 14,
			Color(1, 1, 1, 0.25), 2)
	Ui.label(_ui, "الخريطة", 15, MAP_POS - Vector2(0, 26), MAP_SIZE.x, Ui.MUTED, 700,
			HORIZONTAL_ALIGNMENT_CENTER, 26)
	_map = Control.new()
	_map.position = MAP_POS
	_map.size = MAP_SIZE
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	_ui.add_child(_map)


func _build_bottom() -> void:
	_feed = VBoxContainer.new()
	_feed.position = Vector2(20, VIEW_Y + VIEW_H + 4)
	_feed.size = Vector2(W - 40, 114)
	_feed.add_theme_constant_override("separation", 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_feed)
	Ui.rect(_ui, Color(0, 0, 0, 0.55), Vector2(0, Ui.H - 110), Vector2(W, 110))
	Ui.paragraph(_ui, "علّق أي شي وابدأ التسلق • لايك = نطّة • فولو = نقطة حفظ\nشير = جناحين ضد الصخور • هدية = طوابق • هدية كبيرة = ترفع الكل",
			21, Vector2(10, Ui.H - 104), Vector2(W - 20, 98), Color(1, 1, 1, 0.9), 600)
	_popup = Ui.panel(_ui, Color("#3b1d4a"), Vector2(60, 470), Vector2(600, 170), 26, Ui.ACCENT, 4)
	_popup.pivot_offset = Vector2(300, 85)
	_popup_text = Ui.paragraph(_popup, "", 34, Vector2(16, 8), Vector2(568, 154), Ui.ACCENT, 800)
	_popup.visible = false


func _build_result() -> void:
	_result = Ui.layer(_ui)
	Ui.rect(_result, Color(0, 0, 0, 0.86), Vector2.ZERO, Vector2(W, Ui.H))
	_res_title = Ui.label(_result, "", 50, Vector2(0, 120), W, Ui.ACCENT, 800, HORIZONTAL_ALIGNMENT_CENTER, 90)
	_res_avatar = Ui.avatar(_result, Vector2(W / 2 - 80, 230), 160, Ui.ACCENT, 6)
	_res_name = Ui.label(_result, "", 44, Vector2(0, 400), W, Color.WHITE, 800, HORIZONTAL_ALIGNMENT_CENTER, 70)
	_res_floor = Ui.label(_result, "", 28, Vector2(0, 465), W, Ui.MUTED, 600, HORIZONTAL_ALIGNMENT_CENTER, 44)
	Ui.label(_result, "ترتيب الجولة", 30, Vector2(0, 550), W, Ui.ACCENT, 800, HORIZONTAL_ALIGNMENT_CENTER, 50)
	for i in 4:
		_res_rows.append(Ui.label(_result, "", 28, Vector2(0, 606 + i * 52), W, Color.WHITE, 600,
				HORIZONTAL_ALIGNMENT_CENTER, 48))
	Ui.label(_result, "لوحة الأبطال (البث كله)", 30, Vector2(0, 840), W, Ui.ACCENT, 800,
			HORIZONTAL_ALIGNMENT_CENTER, 50)
	for i in 3:
		_hall_rows.append(Ui.label(_result, "", 28, Vector2(0, 896 + i * 52), W, Ui.MEDALS[i], 700,
				HORIZONTAL_ALIGNMENT_CENTER, 48))
	_res_clock = Ui.label(_result, "", 26, Vector2(0, 1100), W, Ui.MUTED, 600, HORIZONTAL_ALIGNMENT_CENTER, 44)
	_result.visible = false
