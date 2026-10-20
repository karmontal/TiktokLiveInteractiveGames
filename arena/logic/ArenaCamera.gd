extends RefCounted
## Decides what the arena camera looks at, no nodes, so it can be tested headless.
## In order of importance:
##   1. the island edge breaking away (wide, from the warning's last seconds);
##   2. a giant appearing; 3. a knockout;
##   4. viewers who just dropped in (batched, at most one join shot every join_cooldown_s);
##   5. otherwise the closest fight, mostly the leader's, sometimes a wide orbit of everyone.
## A shot: {"kind": "collapse"|"giant"|"ko"|"join"|"fight"|"wide",
##          "focus": Vector2, "distance": float, "uid": String, "users": Array, "left": seconds}

const WIDE := 24.0
const MEDIUM := 13.0
const CLOSE := 8.5

var join_shot_s := 2.6
var join_cooldown_s := 8.0
var ko_shot_s := 1.8
var ko_cooldown_s := 3.0
var hold_min_s := 4.0
var hold_max_s := 6.5
var wide_chance := 0.2
var leader_weight := 0.5

var rng := RandomNumberGenerator.new()
var shot := {}

var _pending: Array = []
var _join_cd := 0.0
var _ko_cd := 0.0


func reset() -> void:
	shot = {}
	_pending.clear()
	_join_cd = 0.0
	_ko_cd = 0.0


func joined(user: Dictionary) -> void:
	for u in _pending:
		if u["id"] == user["id"]:
			return
	_pending.append(user)


func collapse(seconds: float) -> void:
	shot = _make("collapse", Vector2.ZERO, WIDE, "", [], seconds)


func giant(user: Dictionary, pos: Vector2) -> void:
	if _busy("collapse"):
		return
	shot = _make("giant", pos, MEDIUM, str(user["id"]), [user], 3.0)


func ko(user: Dictionary, pos: Vector2) -> void:
	if _busy("collapse") or _busy("giant") or _ko_cd > 0.0:
		return
	_ko_cd = ko_cooldown_s
	shot = _make("ko", pos, MEDIUM, "", [user], ko_shot_s)


func tick(delta: float, logic) -> Dictionary:
	_join_cd -= delta
	_ko_cd -= delta
	if not shot.is_empty():
		shot["left"] -= delta
	var busy: bool = not shot.is_empty() and shot["left"] > 0.0
	var locked: bool = busy and shot["kind"] in ["collapse", "giant", "ko"]
	if not locked:
		if not _pending.is_empty() and _join_cd <= 0.0 and not (busy and shot["kind"] == "join"):
			_start_join(logic)
		elif not busy:
			_pick(logic)
	var uid: String = shot.get("uid", "")
	if uid != "" and logic.fighters.has(uid) and logic.fighters[uid]["alive"]:
		shot["focus"] = logic.fighters[uid]["pos"]
		if shot["kind"] == "fight":                # frame both fighters
			var other: String = logic.fighters[uid]["target"]
			if logic.fighters.has(other) and logic.fighters[other]["alive"]:
				shot["focus"] = (shot["focus"] + logic.fighters[other]["pos"]) * 0.5
	return shot


func _busy(kind: String) -> bool:
	return not shot.is_empty() and shot["kind"] == kind and shot["left"] > 0.0


func _make(kind: String, focus: Vector2, distance: float, uid: String, users: Array, left: float) -> Dictionary:
	return {"kind": kind, "focus": focus, "distance": distance, "uid": uid, "users": users, "left": left}


func _start_join(logic) -> void:
	var users := _pending.duplicate()
	_pending.clear()
	_join_cd = join_cooldown_s
	var newest: Dictionary = users[-1]
	var uid := str(newest["id"])
	var pos: Vector2 = logic.fighters[uid]["pos"] if logic.fighters.has(uid) else Vector2.ZERO
	shot = _make("join", pos, CLOSE if users.size() == 1 else MEDIUM, uid, users, join_shot_s)


func _pick(logic) -> void:
	var hold := rng.randf_range(hold_min_s, hold_max_s)
	var alive: Array = logic.alive_ids()
	if alive.size() < 2 or rng.randf() < wide_chance:
		shot = _make("wide", Vector2.ZERO, WIDE, "", [], hold)
		return
	var uid: String = alive[rng.randi_range(0, alive.size() - 1)]
	var top: Array = logic.ranking(1)
	if not top.is_empty() and top[0]["alive"] and rng.randf() < leader_weight:
		uid = str(top[0]["user"]["id"])
	var f: Dictionary = logic.fighters[uid]
	shot = _make("fight", f["pos"], CLOSE, uid, [f["user"]], hold)
