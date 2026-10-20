extends Node3D
## Arena brawl screen (720x720, 3D; square so TikTok's comments sit under it, not over it). Rules: logic/ArenaLogic.gd. Camera choices: logic/ArenaCamera.gd.
## Each round picks one of four themes at random (sunset island, volcano, ice, neon rooftop).
## A theme's scenery comes from assets/environments/<theme>.glb when that file exists (made in
## Blender); until then a simple built-in version is drawn. The island itself is always built
## here as five rings, so each one can break away on its own.
## The fighter is assets/characters/fighter.glb: materials Suit, Trim, FacePlate; animations
## idle, run, punch, hit, fall, cheer, kick.

const ArenaLogic := preload("res://logic/ArenaLogic.gd")
const ArenaCamera := preload("res://logic/ArenaCamera.gd")
const Ui := preload("res://core/Ui.gd")

const FIGHTER := "res://assets/characters/fighter.glb"
const ENV_DIR := "res://assets/environments/"
const SKY_DIR := "res://assets/sky/"
const TEX_DIR := "res://assets/textures/"
const W := 720.0
const H := 720.0
const RIGHT := HORIZONTAL_ALIGNMENT_RIGHT
const LEFT := HORIZONTAL_ALIGNMENT_LEFT
const CENTER := HORIZONTAL_ALIGNMENT_CENTER
const GOLD := Color("#ffd23f")
const DANGER := Color("#ff8a8a")
const MUTED := Color("#b8c2d0")
const LOOPED := ["idle", "run", "fall", "cheer"]
const PLAYER_COLORS := ["#7c3aed", "#0e7490", "#be185d", "#b45309", "#15803d", "#1d4ed8", "#a16207",
	"#334155", "#dc2626", "#0d9488", "#c026d3", "#4d7c0f"]
const THEMES := {
	"island": {"name": "جزيرة الغروب", "sun": "#ffe2c4", "energy": 1.3, "ambient": "#ffd9c4",
		"side": "#7a4e30", "rim": "#b4583f", "rim_glow": "#000000", "rim_glow_energy": 0.0, "map": "#56a845"},
	"volcano": {"name": "البركان", "sun": "#ffb070", "energy": 1.2, "ambient": "#ff9a6a",
		"side": "#2a201d", "rim": "#2b2523", "rim_glow": "#ff6a1a", "rim_glow_energy": 0.6, "map": "#4a3f3a"},
	"ice": {"name": "الجليد", "sun": "#dbeeff", "energy": 1.0, "ambient": "#cfe6ff",
		"side": "#9cc8ef", "rim": "#d6f0ff", "rim_glow": "#5fd4ff", "rim_glow_energy": 0.35, "map": "#eef6ff"},
	"rooftop": {"name": "سطح المدينة", "sun": "#d8ccff", "energy": 1.2, "ambient": "#b39cff",
		"side": "#2b2f45", "rim": "#3a2440", "rim_glow": "#ff2f6d", "rim_glow_energy": 0.8, "map": "#5a6188"},
}
const HELP := [["لايك", "ضربة أقوى", "heart", "#ff6b8f"], ["فولو", "درع", "shield", "#7cc4ff"],
	["شير", "اندفاعة", "bolt", "#5eead4"], ["هدية صغيرة", "قلب", "heal", "#3ddc84"],
	["هدية متوسطة", "مطرقة", "hammer", "#c084fc"], ["هدية كبيرة", "عملاق", "star", "#ffd23f"]]

var logic := ArenaLogic.new()
var director := ArenaCamera.new()

var _fighter_scene: PackedScene
var _font: FontFile
var _theme_id := ""
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _scenery: Node3D
var _rings: Array[MeshInstance3D] = []
var _ring_tops: Array[StandardMaterial3D] = []
var _ring_rims: Array[StandardMaterial3D] = []
var _cam: Camera3D
var _cam_focus := Vector3.ZERO
var _cam_dist := 24.0
var _cam_yaw := 0.6
var _shake_cam := 0.0
var _views := {}                         # uid -> view dict
var _shot := {}
var _blink := 0.0
var _last_burst := -1.0

# HUD
var _ui: Control
var _hud: Control                        # everything shown while fighting
var _timer: Label
var _alive: Label
var _total: Label
var _leaders: Array[Dictionary] = []
var _radar: Control
var _caption: Panel
var _caption_text: Label
var _warn: Panel
var _warn_text: Label
var _banner: Panel                       # lobby countdown, or the last one standing holding out
var _banner_title: Label
var _banner_big: Label
var _banner_sub: Label
var _theme_badge: Label
var _feed: VBoxContainer
var _popup: Panel
var _popup_text: Label
var _popup_tween: Tween
var _status: Label
var _result: Control
var _res_round: Label
var _res_title: Label
var _res_name: Label
var _res_stats: Label
var _res_rows: Array[Dictionary] = []
var _hall: Array[Dictionary] = []
var _hall_empty: Label
var _res_clock: Label
var _avatars: Array[Panel] = []
var _users := {}


func _ready() -> void:
	Music.play("arena_battle")
	_font = load("res://assets/fonts/Cairo.ttf")
	_fighter_scene = load(FIGHTER)
	_build_world()
	_build_hud()
	EventBus.event_received.connect(_on_event)
	EventBus.connection_changed.connect(_on_connection)
	AvatarCache.avatar_ready.connect(_on_avatar)
	_on_connection(EventBus.connected)
	logic.set_host(_host_name())
	_apply(logic.start())


## The streamer's name for the house fighters: user arg --host=<name>, else env TIKTOK_USERNAME.
func _host_name() -> String:
	var host := OS.get_environment("TIKTOK_USERNAME")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--host="):
			host = arg.trim_prefix("--host=")
	host = host.trim_prefix("@")
	return host if host != "" and host != "mock" else "المضيف"


func _process(delta: float) -> void:
	_blink += delta
	_apply(logic.tick(delta))
	if logic.phase != "result":
		_shot = director.tick(delta, logic)
	_update_views(delta)
	_update_camera(delta)
	_update_rings()
	_update_hud()


# ---------------------------------------------------------------- events

func _on_event(ev: Dictionary) -> void:
	_apply(logic.handle(ev))


func _apply(effects: Array[Dictionary]) -> void:
	for fx in effects:
		match fx["kind"]:
			"round_start":
				_start_round(fx)
			"joined":
				_add_view(fx["user"], true)
				director.joined(fx["user"])
			"punch":
				_punch(fx)
			"shield":
				_say("%s عمل فولو: درع بيصد ضربة" % _name(fx["user"]), Color("#7cc4ff"), "shield")
			"shield_break":
				_burst(_pos3(fx["user"]) + Vector3(0, 2.4, 0), "صدّ!", Color("#7cc4ff"))
			"dash":
				_say("%s عمل شير: اندفاعة!" % _name(fx["user"]), Color("#5eead4"), "bolt")
				_play(str(fx["user"]["id"]), "kick", 0.45)
			"heal":
				_say("قلب من %s: رجعت قوته كاملة" % _name(fx["user"]), Ui.GOOD, "heal")
				_burst(_pos3(fx["user"]) + Vector3(0, 2.6, 0), "+", Ui.GOOD)
			"hammer":
				_say("%s معه مطرقة لـ 15 ثانية!" % _name(fx["user"]), Color("#c084fc"), "hammer")
				_show_popup("%s\nمطرقة!" % _name(fx["user"]))
			"giant":
				_say("%s صار عملاق لـ 10 ثواني!" % _name(fx["user"]), GOLD, "star")
				_show_popup("%s صار عملاق!\n%s" % [_name(fx["user"]), fx["gift"].get("name", "")])
				var uid := str(fx["user"]["id"])
				if logic.fighters.has(uid):
					director.giant(fx["user"], logic.fighters[uid]["pos"])
			"shockwave":
				_shockwave(_pos3(fx["user"]))
			"ko":
				_ko(fx)
			"warning":
				director.collapse(logic.warn_s + 2.5)
			"fight_start":
				_say("يلا! المعركة بلّشت، آخر واحد صامد بيفوز", GOLD, "swords")
				_show_popup("قتال!\n%d مقاتل" % fx["fighters"])
			"alone":
				_say("%s لحاله بالساحة! انزل وتحدّاه" % _name(fx["user"]), GOLD, "star")
			"alone_broken":
				_say("نزل متحدّي جديد! المعركة رجعت", Ui.GOOD, "swords")
			"collapse":
				_collapse(fx["stage"])
			"round_end":
				_show_result(fx)


func _on_connection(connected: bool) -> void:
	_status.text = "● متصل" if connected else "● غير متصل"
	_status.add_theme_color_override("font_color", Ui.GOOD if connected else Color("#ff5c5c"))


func _on_avatar(user_id: String, texture: Texture2D) -> void:
	for holder in _avatars:
		if holder.get_meta("uid", "") == user_id:
			Ui.set_avatar(holder, _users.get(user_id, {}), texture)
	if _views.has(user_id):
		_views[user_id]["face"].albedo_texture = texture


func _name(user) -> String:
	return str(user.get("name", "?")) if user is Dictionary else "?"


func _color(uid: String) -> Color:
	return Color(PLAYER_COLORS[absi(hash(uid)) % PLAYER_COLORS.size()])


# ---------------------------------------------------------------- rounds

func _start_round(fx: Dictionary) -> void:
	_result.visible = false
	director.reset()
	for uid in _views.keys():
		_views[uid]["root"].queue_free()
	_views.clear()
	var options := THEMES.keys().filter(func(t): return t != _theme_id)
	_apply_theme(options[randi() % options.size()])
	for uid in logic.fighters:
		_add_view(logic.fighters[uid]["user"], true)
	_say("الجولة %d: %s! علّق أي شي وانزل عالساحة" % [fx["round"], THEMES[_theme_id]["name"]], GOLD, "swords")


func _show_result(fx: Dictionary) -> void:
	var winner: Dictionary = fx["winner"]
	_result.visible = true
	_caption.visible = false
	_warn.visible = false
	_popup.visible = false
	_res_round.text = "الجولة %d خلصت" % logic.round_no
	for uid in _views:
		_views[uid]["root"].visible = false
	if winner.is_empty():
		_res_title.text = "ما حدا لعب هالجولة"
		_res_name.text = "علّق أي شي وانزل عالساحة!"
		_res_stats.text = ""
	else:
		var uid := str(winner["user"]["id"])
		_res_title.text = "آخر واحد صامد!" if winner["last_standing"] else "بطل الساحة!"
		_res_name.text = _name(winner["user"])
		var parts: PackedStringArray = ["صمد للآخر" if winner["survived"] else "وقع بس الأكثر إقصاء"]
		parts.append("%d إقصاء" % winner["kos"])
		if winner["gifts"] > 0:
			parts.append("%d هدايا" % winner["gifts"])
		_res_stats.text = " · ".join(parts)
		if _views.has(uid) and _views[uid]["out"]:
			_views[uid]["root"].queue_free()
			_views.erase(uid)
		if not _views.has(uid):
			_add_view(winner["user"], false)
		var v: Dictionary = _views[uid]
		v["root"].visible = true
		v["root"].position = Vector3.ZERO
		v["root"].rotation = Vector3.ZERO
		v["root"].scale = Vector3.ONE
		v["winner"] = true
		v["shield"].visible = false
		v["hammer"].visible = false
		v["dmg"].text = ""
		v["label"].visible = false
		v["ap"].play("cheer")
	var top: Array = fx["top"]
	for i in _res_rows.size():
		var row: Dictionary = _res_rows[i]
		row["box"].visible = i < top.size()
		if i < top.size():
			_set_avatar(row["holder"], top[i]["user"])
			Ui.restyle(row["holder"], _color(str(top[i]["user"]["id"])), Color.WHITE, 2)
			row["name"].text = _name(top[i]["user"])
			row["kos"].text = "%d إقصاء" % top[i]["kos"]
	var hall: Array = fx["hall"]
	_hall_empty.visible = hall.is_empty()
	for i in _hall.size():
		var card: Dictionary = _hall[i]
		card["box"].visible = i < hall.size()
		if i < hall.size():
			_set_avatar(card["holder"], hall[i]["user"])
			Ui.restyle(card["holder"], _color(str(hall[i]["user"]["id"])), Ui.MEDALS[i], 3)
			card["name"].text = _name(hall[i]["user"])
			card["line"].text = "%s · %d إقصاء" % [_wins_text(hall[i]["wins"]), hall[i]["kos"]]


static func _wins_text(n: int) -> String:
	if n == 1:
		return "فاز مرة"
	if n == 2:
		return "فاز مرتين"
	if n <= 10:
		return "فاز %d مرات" % n
	return "فاز %d مرة" % n


# ---------------------------------------------------------------- fighters

func _add_view(user: Dictionary, drop: bool) -> void:
	var uid := str(user["id"])
	_users[uid] = user
	if _views.has(uid):
		return
	var root := Node3D.new()
	add_child(root)
	var model: Node3D = _fighter_scene.instantiate()
	root.add_child(model)
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	for anim in LOOPED:
		if ap.has_animation(anim):
			ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var color := _color(uid)
	var suit: StandardMaterial3D = mi.mesh.surface_get_material(0).duplicate()
	suit.albedo_color = color
	suit.emission_enabled = true
	suit.emission = color.lightened(0.3)
	suit.emission_energy_multiplier = 0.0
	mi.set_surface_override_material(0, suit)
	var trim: StandardMaterial3D = mi.mesh.surface_get_material(1).duplicate()
	trim.albedo_color = color.lightened(0.5)
	mi.set_surface_override_material(1, trim)
	var face := StandardMaterial3D.new()
	var tex := AvatarCache.get_avatar(uid, str(user.get("avatar", "")))
	face.albedo_texture = tex if tex else AvatarCache.placeholder(color.lightened(0.6))
	mi.set_surface_override_material(2, face)

	var label := _label3d(_name(user), 40, Vector3(0, 2.45, 0))
	root.add_child(label)
	var dmg := _label3d("", 34, Vector3(0, 2.2, 0))
	root.add_child(dmg)

	var shield := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.25
	sphere.height = 2.5
	shield.mesh = sphere
	shield.position.y = 1.0
	shield.material_override = _glass(Color(0.49, 0.77, 1.0, 0.28))
	shield.visible = false
	root.add_child(shield)

	var hammer := _hammer_mesh()
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var hand := BoneAttachment3D.new()
	hand.bone_name = "hand.R"
	skel.add_child(hand)
	hand.add_child(hammer)
	hammer.visible = false

	_views[uid] = {"root": root, "ap": ap, "suit": suit, "face": face, "label": label, "dmg": dmg,
			"shield": shield, "hammer": hammer, "lock": 0.0, "last": Vector2.INF, "out": false,
			"out_vel": Vector3.ZERO, "out_t": 0.0, "winner": false}
	ap.play("fall" if drop else "idle")
	if drop:
		_beam(uid)


func _label3d(text: String, font_size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = font_size
	l.outline_size = 12
	l.pixel_size = 0.0045
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	return l


func _hammer_mesh() -> Node3D:
	var h := Node3D.new()
	var handle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 1.1
	handle.mesh = cyl
	handle.position.y = 0.45
	handle.material_override = _flat(Color("#8a5a3a"))
	h.add_child(handle)
	var head := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.38, 0.38)
	head.mesh = box
	head.position.y = 1.0
	head.material_override = _flat(Color("#9aa5b1"))
	h.add_child(head)
	return h


func _play(uid: String, anim: String, lock: float) -> void:
	if not _views.has(uid) or _views[uid]["out"]:
		return
	var v: Dictionary = _views[uid]
	v["ap"].stop()
	v["ap"].play(anim)
	v["lock"] = lock


func _update_views(delta: float) -> void:
	for uid in _views.keys():
		var v: Dictionary = _views[uid]
		var root: Node3D = v["root"]
		if v["winner"]:
			root.rotation.y = sin(_blink * 0.9) * 0.5      # sways, but keeps facing the camera
			continue
		if v["out"]:
			v["out_t"] += delta
			v["out_vel"].y -= 25.0 * delta
			root.position += v["out_vel"] * delta
			root.rotation.x += delta * 6.0
			if v["out_t"] > 3.0:
				root.queue_free()
				_views.erase(uid)
			continue
		if not logic.fighters.has(uid):
			continue
		var f: Dictionary = logic.fighters[uid]
		var pos: Vector2 = f["pos"]
		var y: float = f["drop"] / logic.drop_s * 12.0 if f["drop"] > 0.0 else 0.0
		root.position = Vector3(pos.x, y, pos.y)
		var facing: Vector2 = f["facing"]
		root.rotation.y = lerp_angle(root.rotation.y, atan2(facing.x, facing.y), minf(1.0, delta * 10.0))
		var size: float = logic.size_of(f)
		root.scale = root.scale.lerp(Vector3.ONE * size, minf(1.0, delta * 6.0))
		v["shield"].visible = f["shield"]
		v["hammer"].visible = f["hammer"] > 0.0
		v["suit"].emission_energy_multiplier = f["power"] * 0.9
		var d: int = roundi(f["damage"])
		v["dmg"].text = "%d%%" % d if d > 0 else ""
		v["dmg"].modulate = Color.WHITE.lerp(Color("#ff4d4d"), clampf(d / 120.0, 0.0, 1.0))
		v["lock"] = maxf(0.0, v["lock"] - delta)
		var moved: float = pos.distance_to(v["last"]) / maxf(delta, 0.001) if v["last"] != Vector2.INF else 0.0
		v["last"] = pos
		if v["lock"] > 0.0:
			continue
		var want := "idle"
		if f["drop"] > 0.0:
			want = "fall"
		elif moved > 0.6:
			want = "run"
		if v["ap"].current_animation != want:
			v["ap"].play(want, 0.15)


func _pos3(user: Dictionary) -> Vector3:
	var uid := str(user["id"])
	if _views.has(uid):
		return _views[uid]["root"].position
	return Vector3.ZERO


func _punch(fx: Dictionary) -> void:
	_play(str(fx["by"]["id"]), "punch", 0.35)
	_play(str(fx["target"]["id"]), "hit", 0.3)
	if fx["push"] > 3.2 and _blink - _last_burst > 0.4:   # only the big hits, one at a time
		_last_burst = _blink
		_burst(_pos3(fx["target"]) + Vector3(0, 2.6, 0), "طاخ!", GOLD)


func _ko(fx: Dictionary) -> void:
	var uid := str(fx["user"]["id"])
	var by: Dictionary = fx["by"]
	if by.is_empty():
		_say("%s وقع لحاله برا الساحة" % _name(fx["user"]), MUTED, "swords")
	else:
		_say("%s وقّع %s برا الساحة" % [_name(by), _name(fx["user"])], DANGER, "swords")
	director.ko(fx["user"], fx["pos"])
	if not _views.has(uid):
		return
	var v: Dictionary = _views[uid]
	v["out"] = true
	var vel: Vector2 = fx["vel"]
	var outward: Vector2 = fx["pos"].normalized() if fx["pos"].length() > 0.01 else Vector2.RIGHT
	var push := vel + outward * 4.0
	v["out_vel"] = Vector3(push.x, 6.0, push.y)
	v["ap"].play("fall")
	v["dmg"].text = ""
	_burst(v["root"].position + Vector3(0, 2.8, 0), "خارج!", Color("#ff5c5c"))


# ---------------------------------------------------------------- effects

func _burst(at: Vector3, text: String, color: Color) -> void:
	var l := _label3d(text, 72, at)
	l.outline_size = 18
	l.outline_modulate = color.darkened(0.6)
	l.modulate = color
	l.pixel_size = 0.008
	l.scale = Vector3.ONE * 0.4
	add_child(l)
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "position:y", at.y + 0.8, 0.9)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)


func _beam(uid: String) -> void:
	if not logic.fighters.has(uid):
		return
	var pos: Vector2 = logic.fighters[uid]["pos"]
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 16.0
	m.mesh = cyl
	m.position = Vector3(pos.x, 8.0, pos.y)
	var mat := _glass(Color(0.24, 0.86, 0.52, 0.45))
	m.material_override = mat
	add_child(m)
	var t := m.create_tween()
	t.tween_interval(0.8)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	t.tween_callback(m.queue_free)


func _shockwave(at: Vector3) -> void:
	_shake_cam = 0.6
	var m := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	m.mesh = torus
	m.position = at + Vector3(0, 0.3, 0)
	var mat := _glass(Color(1.0, 0.82, 0.25, 0.8))
	m.material_override = mat
	add_child(m)
	var t := m.create_tween()
	t.tween_property(m, "scale", Vector3(logic.shockwave_radius, 1.0, logic.shockwave_radius), 0.5)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.5)
	t.tween_callback(m.queue_free)


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m


func _glass(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# ---------------------------------------------------------------- camera

func _update_camera(delta: float) -> void:
	if logic.phase == "result":
		# Aimed below the winner: they stand between the title and their name.
		var eye_r := Vector3(0, 1.4, 5.8)
		_cam.transform = _cam.transform.interpolate_with(
				Transform3D(Basis.looking_at(Vector3(0, -0.3, 0) - eye_r), eye_r), minf(1.0, delta * 4.0))
		return
	var focus := Vector3.ZERO
	var dist := ArenaCamera.WIDE
	var pitch := deg_to_rad(38.0)
	if not _shot.is_empty():
		focus = Vector3(_shot["focus"].x, 0.8, _shot["focus"].y)
		dist = _shot["distance"]
		_cam_yaw += delta * (0.18 if _shot["kind"] == "wide" else 0.08)
	_cam_focus = _cam_focus.lerp(focus, minf(1.0, delta * 2.5))
	_cam_dist = lerpf(_cam_dist, dist, minf(1.0, delta * 1.8))
	var offset := Vector3(sin(_cam_yaw) * cos(pitch), sin(pitch), cos(_cam_yaw) * cos(pitch)) * _cam_dist
	var eye := _cam_focus + offset
	if _shake_cam > 0.0:
		_shake_cam -= delta
		eye += Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), 0)
	# Aim a little above the focus so the fight sits under the bars at the top.
	_cam.transform = Transform3D(Basis.looking_at(_cam_focus + Vector3.UP * _cam_dist * 0.14 - eye), eye)


# ---------------------------------------------------------------- world and themes

func _build_world() -> void:
	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = PanoramaSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.environment = e
	add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55, -35, 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)
	_cam = Camera3D.new()
	_cam.fov = 62
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.far = 400.0
	add_child(_cam)
	_cam.current = true


func _apply_theme(id: String) -> void:
	_theme_id = id
	var th: Dictionary = THEMES[id]
	var sky: PanoramaSkyMaterial = _env.environment.sky.sky_material
	sky.panorama = load(SKY_DIR + id + ".jpg")
	_sun.light_color = Color(th["sun"])
	_sun.light_energy = th["energy"]
	_env.environment.ambient_light_color = Color(th["ambient"])
	_theme_badge.text = th["name"]
	_rings.clear()
	_ring_tops.clear()
	_ring_rims.clear()
	if _scenery:
		_scenery.queue_free()
	_scenery = Node3D.new()
	add_child(_scenery)
	var floor_tex: Texture2D = load(TEX_DIR + "floor_" + id + ".jpg")
	var radii: Array = logic.radii
	for k in radii.size():
		var outer: float = radii[k]
		var inner: float = radii[k + 1] if k + 1 < radii.size() else 0.0
		var depth := 1.2 + (radii.size() - 1 - k) * 0.9
		var top := _flat(Color.WHITE)
		top.albedo_texture = floor_tex
		top.uv1_triplanar = true
		top.uv1_scale = Vector3.ONE * 0.22
		var side := _flat(Color(th["side"]))
		var rim := _flat(Color(th["rim"]))
		rim.emission_enabled = true
		rim.emission = Color(th["rim_glow"])
		rim.emission_energy_multiplier = th["rim_glow_energy"]
		for m in [top, side, rim]:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh(inner, outer, depth, k + 1 < radii.size())
		ring.set_surface_override_material(0, top)
		ring.set_surface_override_material(1, side)
		if ring.mesh.get_surface_count() > 2:
			ring.set_surface_override_material(2, rim)
		_scenery.add_child(ring)
		_rings.append(ring)
		_ring_tops.append(top)
		_ring_rims.append(rim)
	var path := ENV_DIR + id + ".glb"
	if ResourceLoader.exists(path):                  # scenery built in Blender
		_scenery.add_child(load(path).instantiate())
	else:
		call("_scenery_" + id)


## A flat ring (a disc when inner is 0). Surfaces: 0 the top, 1 the outer wall and rocky
## underside, 2 (with rim) a band of tiles along the outer edge, slightly raised.
func _ring_mesh(inner: float, outer: float, depth: float, rim: bool) -> ArrayMesh:
	var seg := 96
	var band := 0.55 if rim else 0.0
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var top_outer := outer - band
	for i in seg:
		var o0 := Vector3(cos(TAU * i / seg), 0, sin(TAU * i / seg))
		var o1 := Vector3(cos(TAU * (i + 1) / seg), 0, sin(TAU * (i + 1) / seg))
		st.add_vertex(o0 * top_outer)
		st.add_vertex(o1 * inner)
		st.add_vertex(o1 * top_outer)
		st.add_vertex(o0 * top_outer)
		st.add_vertex(o0 * inner)
		st.add_vertex(o1 * inner)
	st.commit(mesh)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var down := Vector3(0, -depth, 0)
	var lean := 0.55                                 # the wall leans in: a rocky underside
	for i in seg:
		var o0 := Vector3(cos(TAU * i / seg), 0, sin(TAU * i / seg))
		var o1 := Vector3(cos(TAU * (i + 1) / seg), 0, sin(TAU * (i + 1) / seg))
		var j0 := 1.0 + 0.04 * sin(i * 2.3)              # a little roughness on the rock
		var j1 := 1.0 + 0.04 * sin((i + 1) * 2.3)
		st.set_normal((o0 + o1).normalized())
		st.add_vertex(o0 * outer)
		st.add_vertex(o1 * outer)
		st.add_vertex(o1 * outer * lean * j1 + down)
		st.add_vertex(o0 * outer)
		st.add_vertex(o1 * outer * lean * j1 + down)
		st.add_vertex(o0 * outer * lean * j0 + down)
		st.set_normal(Vector3.DOWN)
		st.add_vertex(o0 * outer * lean * j0 + down)
		st.add_vertex(o1 * outer * lean * j1 + down)
		st.add_vertex(down)
	st.commit(mesh)
	if rim:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var blocks := int(outer * TAU / 1.4)
		var up := Vector3(0, 0.1, 0)
		for b in blocks:
			var a0 := TAU * (b + 0.04) / blocks
			var a1 := TAU * (b + 0.96) / blocks
			var lift := up * (1.0 + 0.4 * sin(b * 1.7))   # uneven tiles
			var steps := 3
			for s in steps:
				var t0 := lerpf(a0, a1, float(s) / steps)
				var t1 := lerpf(a0, a1, float(s + 1) / steps)
				var d0 := Vector3(cos(t0), 0, sin(t0))
				var d1 := Vector3(cos(t1), 0, sin(t1))
				var in0 := d0 * (outer - band + 0.04)
				var in1 := d1 * (outer - band + 0.04)
				var out0 := d0 * (outer - 0.02)
				var out1 := d1 * (outer - 0.02)
				st.set_normal(Vector3.UP)
				for v in [out0 + lift, in1 + lift, out1 + lift, out0 + lift, in0 + lift, in1 + lift]:
					st.add_vertex(v)
				st.set_normal((d0 + d1).normalized())
				for v in [out0, out1, out1 + lift, out0, out1 + lift, out0 + lift]:
					st.add_vertex(v)
				st.set_normal(-(d0 + d1).normalized())
				for v in [in0, in1 + lift, in1, in0, in0 + lift, in1 + lift]:
					st.add_vertex(v)
		st.commit(mesh)
	return mesh


func _update_rings() -> void:
	if _theme_id == "":
		return
	var th: Dictionary = THEMES[_theme_id]
	for k in _ring_tops.size():
		var warned: bool = k == logic.stage and logic.warning >= 0.0
		var pulse := 0.5 + 0.5 * sin(_blink * 10.0)
		_ring_tops[k].albedo_color = Color.WHITE.lerp(Color("#ff6b6b"), 0.35 + 0.35 * pulse) if warned else Color.WHITE
		_ring_rims[k].emission = Color("#ff2a2a") if warned else Color(th["rim_glow"])
		_ring_rims[k].emission_energy_multiplier = (0.6 + 1.4 * pulse) if warned else th["rim_glow_energy"]


func _collapse(stage: int) -> void:
	var k := stage - 1
	if k < 0 or k >= _rings.size():
		return
	var ring := _rings[k]
	_shake_cam = 0.8
	var t := ring.create_tween()
	t.tween_property(ring, "position:y", -40.0, 2.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(ring, "rotation:x", randf_range(-0.4, 0.4), 2.5)
	t.tween_callback(ring.hide)
	_say("الحافة انهارت! الساحة صارت أصغر", DANGER, "warn")


## Puts things on a ring so they fall with it when it breaks away.
func _on_ring(k: int, node: Node3D) -> void:
	_rings[k].add_child(node)


func _scenery_island() -> void:
	var lanterns := 10
	for i in lanterns:
		var a := TAU * (i + 0.5) / lanterns
		var post := Node3D.new()
		post.position = Vector3(cos(a), 0, sin(a)) * (logic.radii[0] - 0.28)
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.09
		cyl.height = 1.6
		pole.mesh = cyl
		pole.position.y = 0.9
		pole.material_override = _flat(Color("#5b3d22"))
		post.add_child(pole)
		var lamp := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.36, 0.42, 0.36)
		lamp.mesh = box
		lamp.position.y = 1.85
		lamp.material_override = _glow(Color("#ffc46b"))
		post.add_child(lamp)
		var cap := MeshInstance3D.new()
		var roof := CylinderMesh.new()
		roof.top_radius = 0.02
		roof.bottom_radius = 0.3
		roof.height = 0.22
		roof.radial_segments = 4
		cap.mesh = roof
		cap.position.y = 2.17
		cap.material_override = _flat(Color("#3b2a1c"))
		post.add_child(cap)
		_on_ring(0, post)
	for i in 14:                                     # clouds drifting just under the island
		var cloud := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = randf_range(2.5, 5.0)
		s.height = s.radius * 0.8
		cloud.mesh = s
		var a := randf() * TAU
		var d := randf_range(13.0, 30.0)
		cloud.position = Vector3(cos(a) * d, randf_range(-14.0, -6.0), sin(a) * d)
		cloud.scale = Vector3(1.9, 0.55, 1.3)
		cloud.material_override = _flat(Color("#ffd6e4"))
		_scenery.add_child(cloud)
	for i in 10:                                     # little floating rocks
		var rock := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = randf_range(0.5, 1.3)
		c.bottom_radius = 0.15
		c.height = randf_range(1.0, 2.2)
		c.radial_segments = 6
		rock.mesh = c
		var a := randf() * TAU
		var d := randf_range(11.5, 22.0)
		rock.position = Vector3(cos(a) * d, randf_range(-5.0, 1.5), sin(a) * d)
		rock.rotation.y = randf() * TAU
		var top_m := _flat(Color("#6aa84f"))
		rock.material_override = _flat(Color("#7a4e30"))
		_scenery.add_child(rock)
		var grass := MeshInstance3D.new()
		var g := CylinderMesh.new()
		g.top_radius = c.top_radius
		g.bottom_radius = c.top_radius
		g.height = 0.15
		g.radial_segments = 6
		grass.mesh = g
		grass.position = rock.position + Vector3(0, c.height / 2.0, 0)
		grass.rotation.y = rock.rotation.y
		grass.material_override = top_m
		_scenery.add_child(grass)


func _scenery_volcano() -> void:
	for i in 9:                                      # rock spires standing in the lava
		var spire := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = randf_range(0.4, 1.2)
		c.bottom_radius = c.top_radius * randf_range(2.0, 3.0)
		c.height = randf_range(5.0, 12.0)
		c.radial_segments = 6
		spire.mesh = c
		var a := TAU * i / 9.0 + randf_range(-0.2, 0.2)
		var d := randf_range(14.0, 26.0)
		spire.position = Vector3(cos(a) * d, -9.0 + c.height / 2.0, sin(a) * d)
		spire.material_override = _flat(Color("#231a18"))
		_scenery.add_child(spire)
		var glow := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = c.bottom_radius * 1.6
		disc.bottom_radius = c.bottom_radius * 1.6
		disc.height = 0.1
		glow.mesh = disc
		glow.position = Vector3(spire.position.x, -9.0, spire.position.z)
		glow.material_override = _glow(Color("#ff7a1a"))
		_scenery.add_child(glow)
	for i in 6:                                      # glowing cracks hanging under the island rock
		var vein := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.12, randf_range(1.5, 3.0), 0.12)
		vein.mesh = b
		var a := randf() * TAU
		vein.position = Vector3(cos(a), 0, sin(a)) * (logic.radii[0] * 0.8) + Vector3(0, -1.6, 0)
		vein.rotation.z = randf_range(-0.4, 0.4)
		vein.material_override = _glow(Color("#ff8a2a"))
		_on_ring(0, vein)
	_particles(Color("#ffb347"), Vector3(26, 6, 26), 1.5, 2.0, 140)


func _scenery_ice() -> void:
	for i in 8:                                      # ice floes nearby, some with penguins
		var floe := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = randf_range(1.2, 2.6)
		c.bottom_radius = c.top_radius * 0.9
		c.height = 0.7
		c.radial_segments = 7
		floe.mesh = c
		var a := TAU * i / 8.0 + randf_range(-0.25, 0.25)
		var d := randf_range(13.0, 22.0)
		floe.position = Vector3(cos(a) * d, -4.5, sin(a) * d)
		floe.material_override = _flat(Color("#eef7ff"))
		_scenery.add_child(floe)
		if i % 2 == 0:
			for p in 2:
				var penguin := _penguin()
				penguin.position = floe.position + Vector3(randf_range(-0.6, 0.6), 0.35, randf_range(-0.6, 0.6))
				penguin.rotation.y = randf() * TAU
				_scenery.add_child(penguin)
	for i in 5:                                      # icicles under the island
		var ice := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = randf_range(0.3, 0.6)
		cone.bottom_radius = 0.0
		cone.height = randf_range(1.5, 3.0)
		ice.mesh = cone
		var a := TAU * i / 5.0
		ice.position = Vector3(cos(a), 0, sin(a)) * (logic.radii[0] * 0.7) + Vector3(0, -2.2, 0)
		ice.material_override = _glow(Color("#bfe9ff"))
		_on_ring(0, ice)
	_particles(Color.WHITE, Vector3(24, 2, 24), -1.5, 3.0, 180)


func _penguin() -> Node3D:
	var p := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.18
	cap.height = 0.6
	body.mesh = cap
	body.position.y = 0.3
	body.material_override = _flat(Color("#1d2433"))
	p.add_child(body)
	var belly := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.14
	bs.height = 0.36
	belly.mesh = bs
	belly.position = Vector3(0, 0.27, 0.08)
	belly.material_override = _flat(Color.WHITE)
	p.add_child(belly)
	var beak := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.0
	bc.bottom_radius = 0.04
	bc.height = 0.1
	beak.mesh = bc
	beak.rotation.x = PI / 2.0
	beak.position = Vector3(0, 0.48, 0.18)
	beak.material_override = _flat(Color("#ff9f1c"))
	p.add_child(beak)
	return p


func _scenery_rooftop() -> void:
	var tower := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(19.5, 70, 19.5)
	tower.mesh = b
	tower.position.y = -35.2
	var tm := _flat(Color.WHITE)
	tm.albedo_texture = _windows_texture()
	tm.emission_enabled = true
	tm.emission_texture = tm.albedo_texture
	tm.emission_energy_multiplier = 0.8
	tm.uv1_triplanar = true
	tm.uv1_scale = Vector3.ONE * 0.08
	tower.material_override = tm
	_scenery.add_child(tower)
	var neon := [Color("#ff4fd8"), Color("#36e7ff")]
	for i in 2:                                      # neon rings around the edge
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = logic.radii[0] + 0.1 + i * 0.4
		torus.outer_radius = torus.inner_radius + 0.16
		torus.rings = 128
		ring.mesh = torus
		ring.position.y = 0.12 - i * 0.6
		ring.material_override = _glow(neon[i])
		_on_ring(0, ring)
	for i in 6:                                      # nearby towers with lit windows
		var bld := MeshInstance3D.new()
		var box := BoxMesh.new()
		var h := randf_range(40.0, 75.0)
		box.size = Vector3(randf_range(6, 10), h, randf_range(6, 10))
		bld.mesh = box
		var a := TAU * i / 6.0 + randf_range(-0.3, 0.3)
		var d := randf_range(26.0, 40.0)
		bld.position = Vector3(cos(a) * d, -75.0 + h / 2.0, sin(a) * d)
		bld.material_override = tm
		_scenery.add_child(bld)
		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(box.size.x + 0.2, 0.5, box.size.z + 0.2)
		strip.mesh = sb
		strip.position = bld.position + Vector3(0, h / 2.0 - 0.6, 0)
		strip.material_override = _glow(neon[i % 2])
		_scenery.add_child(strip)


## Dark wall with a grid of randomly lit windows, for the rooftop towers.
func _windows_texture() -> Texture2D:
	var n := 128
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color("#141729"))
	var lit := [Color("#ffd27a"), Color("#8fe8ff"), Color("#ff9be0")]
	for gy in 16:
		for gx in 16:
			var c: Color = lit[randi() % lit.size()] if randf() < 0.45 else Color("#20243d")
			img.fill_rect(Rect2i(gx * 8 + 2, gy * 8 + 2, 4, 5), c)
	return ImageTexture.create_from_image(img)


func _particles(color: Color, box: Vector3, gravity: float, speed: float, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3(0, 1.0 if gravity >= 0.0 else -1.0, 0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	p.mesh = q
	var m := _glow(color)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.material_override = m
	p.position.y = 6.0 if gravity < 0.0 else -6.0
	_scenery.add_child(p)


# ---------------------------------------------------------------- HUD

func _update_hud() -> void:
	var secs := maxi(0, ceili(logic.time_left))
	if logic.phase == "result":
		_res_clock.text = "جولة جديدة بعد %d" % secs
	else:
		_timer.text = "%d:%02d" % [secs / 60, secs % 60] if logic.phase == "fight" else "5:00"
	_update_banner()
	_alive.text = "%d صامد" % logic.alive_ids().size()
	_total.text = "من %d لاعب" % logic.fighters.size()
	_hud.visible = logic.phase != "result"
	_warn.visible = logic.phase == "fight" and logic.warning >= 0.0
	if _warn.visible:
		_warn_text.text = "الحافة بتنهار بعد 0:%02d" % ceili(logic.warning)
	if Engine.get_process_frames() % 8 == 0:
		_refresh_leaders()
		_refresh_caption()
	_radar.queue_redraw()


func _update_banner() -> void:
	var lobby: bool = logic.phase == "lobby"
	var holding: bool = logic.phase == "fight" and logic.alone >= 0.0
	_banner.visible = lobby or holding
	if lobby:
		var joined: int = logic.alive_ids().filter(func(uid): return not logic.is_bot(uid)).size()
		if logic.time_left > 0.0:
			_banner_title.text = "المعركة بتبلّش بعد"
			_banner_big.text = str(ceili(logic.time_left))
		else:
			_banner_title.text = "بنستنى لاعب كمان"
			_banner_big.text = "..."
		_banner_sub.text = "علّق أو ابعت %d لايكات وانزل! نزل %d لحد هلأ" % [logic.join_likes, joined]
		Ui.restyle(_banner, Color(0.02, 0.03, 0.08, 0.8), GOLD, 3)
	elif holding:
		var last: Array = logic.alive_ids()
		var who: String = _name(logic.fighters[last[0]]["user"]) if not last.is_empty() else ""
		_banner_title.text = "%s لحاله بالساحة!" % who
		_banner_big.text = str(ceili(logic.alone))
		_banner_sub.text = "بيفوز إذا ما حدا نزل يتحدّاه، علّق وانزل!"
		Ui.restyle(_banner, Color(0.1, 0.03, 0.03, 0.82), DANGER, 3)


func _refresh_leaders() -> void:
	var top := logic.ranking(3)
	for i in _leaders.size():
		var l: Dictionary = _leaders[i]
		var has: bool = i < top.size() and top[i]["kos"] > 0
		l["box"].modulate.a = 1.0 if has else 0.35
		if has:
			_set_avatar(l["holder"], top[i]["user"])
			Ui.restyle(l["holder"], _color(str(top[i]["user"]["id"])), Ui.MEDALS[i], 3)
			l["name"].text = _name(top[i]["user"])
			l["kos"].text = "%d إقصاء" % top[i]["kos"]
		else:
			l["name"].text = "—"
			l["kos"].text = ""


func _refresh_caption() -> void:
	var text := ""
	var color := Color.WHITE
	match _shot.get("kind", ""):
		"fight":
			var f: Dictionary = logic.fighters.get(_shot["uid"], {})
			var other: Dictionary = logic.fighters.get(f.get("target", ""), {})
			if not f.is_empty():
				text = _name(f["user"]) if other.is_empty() else "معركة: %s ضد %s" % [_name(f["user"]), _name(other["user"])]
			color = GOLD
		"join":
			var users: Array = _shot["users"]
			text = "أهلا بـ %s" % " و".join(users.slice(0, 2).map(func(u): return _name(u)))
			if users.size() > 2:
				text += " و%d كمان" % (users.size() - 2)
			color = Ui.GOOD
		"ko":
			text = "خارج! %s" % _name(_shot["users"][0])
			color = DANGER
		"giant":
			text = "عملاق: %s" % _name(_shot["users"][0])
			color = GOLD
		"wide":
			text = "الساحة كلها" if logic.alive_ids().size() > 1 else "علّق أي شي وانزل عالساحة!"
	_caption.visible = text != "" and logic.phase == "fight" and not _warn.visible and not _banner.visible
	_caption_text.text = text
	_caption_text.add_theme_color_override("font_color", color)
	Ui.restyle(_caption, Color(0.02, 0.03, 0.08, 0.78), color, 2)


func _draw_radar() -> void:
	var c := Vector2(55, 72)
	var px: float = 44.0 / logic.radii[0]
	var th: Dictionary = THEMES.get(_theme_id, THEMES["island"])
	if logic.warning >= 0.0:
		_radar.draw_circle(c, logic.radius() * px, Color(1, 0.36, 0.36, 0.55 + 0.3 * sin(_blink * 10.0)))
		_radar.draw_circle(c, logic.next_radius() * px, Color(th["map"]))
	else:
		_radar.draw_circle(c, logic.radius() * px, Color(th["map"]))
	_radar.draw_arc(c, logic.radius() * px, 0, TAU, 48, Color(1, 1, 1, 0.5), 2)
	var top := logic.ranking(3).map(func(e): return str(e["user"]["id"]))
	for uid in logic.alive_ids():
		var f: Dictionary = logic.fighters[uid]
		var p: Vector2 = c + f["pos"] * px
		var rank: int = top.find(uid)
		if rank >= 0 and f["kos"] > 0:
			_radar.draw_circle(p, 5.5, Color.BLACK)
			_radar.draw_circle(p, 4.2, Ui.MEDALS[rank])
		else:
			_radar.draw_circle(p, 2.6, _color(uid).lightened(0.4))
	if not _shot.is_empty() and logic.phase == "fight":
		_radar.draw_arc(c + _shot["focus"] * px, _shot["distance"] * px * 0.35, 0, TAU, 24, Color.WHITE, 1.5)


## Small icons on a 24x24 grid, scaled to the control.
func _draw_icon(ci: Control, kind: String, color: Color) -> void:
	var k := ci.size.x / 24.0
	var w := 2.4 * k
	match kind:
		"swords":
			for seg in [[Vector2(4, 4), Vector2(14, 14)], [Vector2(14, 18), Vector2(18, 14)], [Vector2(16, 16), Vector2(20, 20)],
					[Vector2(20, 4), Vector2(10, 14)], [Vector2(6, 14), Vector2(10, 18)], [Vector2(8, 16), Vector2(4, 20)]]:
				ci.draw_line(seg[0] * k, seg[1] * k, color, w)
		"heart", "heal":
			ci.draw_circle(Vector2(7.5, 8.5) * k, 5.2 * k, color)
			ci.draw_circle(Vector2(16.5, 8.5) * k, 5.2 * k, color)
			ci.draw_colored_polygon(_pts([Vector2(2.6, 10.5), Vector2(21.4, 10.5), Vector2(12, 21)], k), color)
			if kind == "heal":
				ci.draw_line(Vector2(12, 8) * k, Vector2(12, 15) * k, Color("#0b2a1a"), w)
				ci.draw_line(Vector2(8.5, 11.5) * k, Vector2(15.5, 11.5) * k, Color("#0b2a1a"), w)
		"shield":
			ci.draw_polyline(_pts([Vector2(12, 2), Vector2(20, 5), Vector2(20, 11), Vector2(16, 18), Vector2(12, 22),
					Vector2(8, 18), Vector2(4, 11), Vector2(4, 5), Vector2(12, 2)], k), color, w)
		"bolt":
			ci.draw_colored_polygon(_pts([Vector2(13, 2), Vector2(5, 13), Vector2(11, 13), Vector2(10, 22),
					Vector2(19, 10), Vector2(13, 10)], k), color)
		"hammer":
			ci.draw_line(Vector2(4, 20) * k, Vector2(13, 11) * k, color, w)
			ci.draw_colored_polygon(_pts([Vector2(11, 5), Vector2(17, 3), Vector2(21, 7), Vector2(19, 13)], k), color)
		"star":
			ci.draw_colored_polygon(_pts([Vector2(12, 2), Vector2(15, 9), Vector2(22, 9), Vector2(16.5, 13.5),
					Vector2(18.5, 21), Vector2(12, 16.5), Vector2(5.5, 21), Vector2(7.5, 13.5), Vector2(2, 9), Vector2(9, 9)], k), color)
		"clock":
			ci.draw_arc(Vector2(12, 13) * k, 8 * k, 0, TAU, 24, color, w)
			ci.draw_polyline(_pts([Vector2(12, 9), Vector2(12, 13), Vector2(15, 15)], k), color, w)
			ci.draw_line(Vector2(9, 2) * k, Vector2(15, 2) * k, color, w)
		"warn":
			ci.draw_polyline(_pts([Vector2(12, 3), Vector2(22, 20), Vector2(2, 20), Vector2(12, 3)], k), color, w)
			ci.draw_line(Vector2(12, 10) * k, Vector2(12, 14) * k, color, w)
			ci.draw_circle(Vector2(12, 17.3) * k, 1.3 * k, color)


func _pts(list: Array, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in list:
		out.append(p * k)
	return out


func _icon(parent: Control, kind: String, pos: Vector2, size: float, color: Color) -> Control:
	var ci := Control.new()
	ci.position = pos
	ci.size = Vector2(size, size)
	ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ci.draw.connect(_draw_icon.bind(ci, kind, color))
	parent.add_child(ci)
	return ci


func _say(text: String, color: Color, icon: String) -> void:
	var line := Control.new()
	line.custom_minimum_size = Vector2(W - 40, 32)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon(line, icon, Vector2(W - 62, 6), 20, color)
	Ui.label(line, text, 18, Vector2.ZERO, W - 74, color, 700, RIGHT, 32)
	_feed.add_child(line)
	while _feed.get_child_count() > 3:
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
	_popup_tween.tween_interval(2.2)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.4)
	_popup_tween.tween_callback(func(): _popup.visible = false)


func _avatar(parent: Node, pos: Vector2, diameter: float, ring: Color, ring_width := 3) -> Panel:
	var a := Ui.avatar(parent, pos, diameter, ring, ring_width)
	_avatars.append(a)
	return a


func _set_avatar(holder: Panel, user: Dictionary) -> void:
	var uid := str(user.get("id", ""))
	_users[uid] = user
	Ui.set_avatar(holder, user, AvatarCache.get_avatar(uid, str(user.get("avatar", ""))))


func _gradient(parent: Control, size: Vector2, top: Color, bottom: Color) -> Control:
	var c := Control.new()
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
			PackedColorArray([top, top, bottom, bottom])))
	parent.add_child(c)
	return c


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Ui.root(layer)
	_hud = Ui.layer(_ui)

	# Header, then what each interaction does: all at the top, TikTok's comments cover the bottom.
	_gradient(_hud, Vector2(W, 250), Color(0.02, 0.03, 0.08, 0.92), Color(0.02, 0.03, 0.08, 0.0))
	_icon(_hud, "swords", Vector2(474, 12), 32, GOLD)
	Ui.label(_hud, "معركة الساحة", 34, Vector2(210, 0), 260, GOLD, 900, CENTER, 56)
	_status = Ui.label(_hud, "", 11, Vector2(W - 120, -2), 112, Color.WHITE, 500, RIGHT, 16)
	_alive = Ui.label(_hud, "", 19, Vector2(W - 170, 10), 156, Color.WHITE, 900, RIGHT, 26)
	_total = Ui.label(_hud, "", 13, Vector2(W - 170, 33), 156, MUTED, 700, RIGHT, 20)
	var pill := Ui.panel(_hud, Color(1, 1, 1, 0.1), Vector2(14, 10), Vector2(106, 36), 18)
	_icon(pill, "clock", Vector2(12, 8), 20, Color.WHITE)
	_timer = Ui.label(pill, "", 21, Vector2(36, 0), 62, Color.WHITE, 800, LEFT, 36)
	_timer.text_direction = Control.TEXT_DIRECTION_LTR

	Ui.panel(_hud, Color(0.02, 0.03, 0.08, 0.9), Vector2(6, 56), Vector2(W - 12, 96), 18, Color(1, 1, 1, 0.14), 1)
	var col_w := (W - 16) / HELP.size()
	for i in HELP.size():
		var h: Array = HELP[i]
		var x := W - 8 - col_w * (i + 1)              # first item on the right
		var color := Color(h[3])
		var box := Ui.panel(_hud, Color(color, 0.18), Vector2(x + col_w / 2 - 22, 62), Vector2(44, 44), 14)
		_icon(box, h[2], Vector2(9, 9), 26, color)
		Ui.label(_hud, h[0], 16, Vector2(x - 4, 104), col_w + 8, Color.WHITE, 900, CENTER, 24)
		Ui.label(_hud, h[1], 15, Vector2(x, 125), col_w, color.lightened(0.25), 700, CENTER, 22)

	for i in 3:
		var x := W - 12.0 - 232.0 * (i + 1) + 8.0     # first place on the right
		var box := Ui.panel(_hud, Color(0.02, 0.03, 0.08, 0.6), Vector2(x, 158), Vector2(224, 50), 25, Ui.MEDALS[i], 2)
		var badge := Ui.panel(box, Ui.MEDALS[i], Vector2(8, 12), Vector2(26, 26), 13)
		Ui.label(badge, str(i + 1), 15, Vector2.ZERO, 26, Color("#1a1300"), 900, CENTER, 26)
		var holder := _avatar(box, Vector2(176, 5), 40, Ui.MEDALS[i])
		var nm := Ui.label(box, "—", 16, Vector2(40, 2), 130, Color.WHITE, 800, RIGHT, 24)
		var kos := Ui.label(box, "", 13, Vector2(40, 24), 130, Ui.MEDALS[i], 700, RIGHT, 22)
		_leaders.append({"box": box, "holder": holder, "name": nm, "kos": kos})

	Ui.panel(_hud, Color(0.02, 0.04, 0.09, 0.72), Vector2(12, 214), Vector2(110, 126), 16, Color(1, 1, 1, 0.22), 2)
	Ui.label(_hud, "الساحة", 12, Vector2(12, 215), 110, Color("#cfd8e3"), 800, CENTER, 20)
	_radar = Control.new()
	_radar.position = Vector2(12, 214)
	_radar.size = Vector2(110, 126)
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar.draw.connect(_draw_radar)
	_hud.add_child(_radar)
	var tb := Ui.panel(_hud, Color(0.02, 0.03, 0.08, 0.72), Vector2(W - 172, 216), Vector2(160, 30), 15, Color(1, 1, 1, 0.3), 1)
	_theme_badge = Ui.label(tb, "", 14, Vector2(6, 0), 148, Color("#e2e8f0"), 800, CENTER, 30)

	_caption = Ui.panel(_hud, Color(0.02, 0.03, 0.08, 0.78), Vector2(170, 216), Vector2(380, 38), 19, GOLD, 2)
	_caption_text = Ui.label(_caption, "", 17, Vector2(10, 0), 360, GOLD, 800, CENTER, 38)
	_caption.visible = false
	_warn = Ui.panel(_hud, Color("#5a1414"), Vector2(200, 216), Vector2(320, 38), 19, DANGER, 2)
	_icon(_warn, "warn", Vector2(284, 8), 22, Color("#ffd0d0"))
	_warn_text = Ui.label(_warn, "", 17, Vector2(10, 0), 270, Color("#ffd0d0"), 800, CENTER, 38)
	_warn.visible = false
	_banner = Ui.panel(_hud, Color(0.02, 0.03, 0.08, 0.8), Vector2(150, 262), Vector2(420, 128), 24, GOLD, 3)
	_banner_title = Ui.label(_banner, "", 21, Vector2(12, 2), 396, Color.WHITE, 800, CENTER, 34)
	_banner_big = Ui.label(_banner, "", 46, Vector2(12, 28), 396, GOLD, 900, CENTER, 64)
	_banner_big.text_direction = Control.TEXT_DIRECTION_LTR
	_banner_sub = Ui.label(_banner, "", 16, Vector2(12, 90), 396, Color("#e2e8f0"), 700, CENTER, 30)
	_banner.visible = false

	_feed = VBoxContainer.new()
	_feed.position = Vector2(20, H - 104)
	_feed.size = Vector2(W - 40, 100)
	_feed.add_theme_constant_override("separation", 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_feed)

	_popup = Ui.panel(_hud, Color("#3b1d4a"), Vector2(90, 290), Vector2(540, 150), 24, GOLD, 4)
	_popup.pivot_offset = Vector2(270, 75)
	_popup_text = Ui.paragraph(_popup, "", 30, Vector2(14, 6), Vector2(512, 138), GOLD, 800)
	_popup.visible = false

	# Result: the winner cheers in the middle, round KOs on the right, the stream's champions on the left.
	_result = Ui.layer(_ui)
	_gradient(_result, Vector2(W, 200), Color(0.05, 0.03, 0.15, 0.95), Color(0.05, 0.03, 0.15, 0.0))
	Ui.panel(_result, Color(0.05, 0.03, 0.15, 0.9), Vector2(0, 412), Vector2(W, H - 412))
	_res_round = Ui.label(_result, "", 18, Vector2(0, 8), W, Color("#e9d5ff"), 800, CENTER, 30)
	_res_title = Ui.label(_result, "", 46, Vector2(0, 32), W, GOLD, 900, CENTER, 70)
	_res_name = Ui.label(_result, "", 36, Vector2(0, 330), W, Color.WHITE, 900, CENTER, 50)
	_res_stats = Ui.label(_result, "", 17, Vector2(0, 378), W, Color("#f5d0fe"), 700, CENTER, 30)
	Ui.label(_result, "أكثر إقصاء بالجولة", 19, Vector2(372, 418), 336, GOLD, 900, RIGHT, 32)
	for i in 4:
		var box := Ui.panel(_result, Color(1, 1, 1, 0.07), Vector2(372, 454 + i * 52), Vector2(336, 46), 14)
		Ui.label(box, str(i + 1), 18, Vector2(304, 0), 28, Color("#e9d5ff"), 900, CENTER, 46)
		var holder := _avatar(box, Vector2(266, 6), 34, Color.WHITE, 2)
		var nm := Ui.label(box, "", 17, Vector2(96, 0), 164, Color.WHITE, 800, RIGHT, 46)
		var kos := Ui.label(box, "", 15, Vector2(10, 0), 84, Color("#ff8a8a"), 800, LEFT, 46)
		_res_rows.append({"box": box, "holder": holder, "name": nm, "kos": kos})
	Ui.label(_result, "أبطال البث", 19, Vector2(12, 418), 336, GOLD, 900, RIGHT, 32)
	for i in 3:
		var box := Ui.panel(_result, Color(1, 1, 1, 0.06), Vector2(12, 454 + i * 52), Vector2(336, 46), 14, Ui.MEDALS[i], 2)
		var holder := _avatar(box, Vector2(290, 6), 34, Ui.MEDALS[i])
		var nm := Ui.label(box, "", 17, Vector2(128, 0), 156, Color.WHITE, 800, RIGHT, 46)
		var line := Ui.label(box, "", 13, Vector2(10, 0), 118, Ui.MEDALS[i], 800, LEFT, 46)
		_hall.append({"box": box, "holder": holder, "name": nm, "line": line})
	_hall_empty = Ui.label(_result, "لسا ما فاز حدا من المشاهدين، انزل وكون أول بطل!", 15, Vector2(12, 454), 336, MUTED, 700, CENTER, 46)
	var clock := Ui.panel(_result, Color(1, 1, 1, 0.1), Vector2(12, H - 52), Vector2(336, 42), 21)
	_icon(clock, "clock", Vector2(296, 11), 20, Color("#f3e8ff"))
	_res_clock = Ui.label(clock, "", 18, Vector2(12, 0), 276, Color("#f3e8ff"), 800, CENTER, 42)
	_result.visible = false
