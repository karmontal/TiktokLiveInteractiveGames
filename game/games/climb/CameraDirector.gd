extends RefCounted
## Decides what the climb camera looks at, no nodes, so it can be tested headless.
## In order of importance:
##   1. falling rocks, from the warning until a moment after they land;
##   2. viewers who just joined (joins that arrive during a shot or its cooldown are
##      batched into the next join shot, so a busy LIVE does not pin the camera to the ground);
##   3. otherwise a random climber, mostly the leader and the runner-up.
## A shot: {"kind": "hazard"|"join"|"leader"|"second"|"climber"|"ground",
##          "floor": float, "uid": String, "users": Array, "left": seconds}

var join_shot_s := 3.0
var join_cooldown_s := 8.0       # from the start of one join shot to the next
var hazard_after_s := 1.2        # stay on the band after the rocks land
var hold_min_s := 4.0
var hold_max_s := 6.5
var leader_weight := 0.45
var second_weight := 0.25        # the rest goes to a random other climber

var rng := RandomNumberGenerator.new()
var shot := {}

var _pending: Array = []         # users waiting for a join shot
var _cooldown := 0.0
var _last_uid := ""


func reset() -> void:
	shot = {}
	_pending.clear()
	_cooldown = 0.0
	_last_uid = ""


func joined(user: Dictionary) -> void:
	for u in _pending:
		if u["id"] == user["id"]:
			return
	_pending.append(user)


## Rocks announced over floors [from, to]; they land after warning_s.
func hazard(from: float, to: float, warning_s: float) -> void:
	shot = {"kind": "hazard", "floor": (from + to) / 2.0, "uid": "", "users": [],
			"left": warning_s + hazard_after_s}


## Advances time and returns the current shot. `logic` is the ClimbLogic being shown.
func tick(delta: float, logic) -> Dictionary:
	_cooldown -= delta
	if not shot.is_empty():
		shot["left"] -= delta
	var busy: bool = not shot.is_empty() and shot["left"] > 0.0
	if busy and shot["kind"] == "hazard":
		return shot
	if not _pending.is_empty() and _cooldown <= 0.0 and not (busy and shot["kind"] == "join"):
		_start_join(logic)
	elif not busy:
		_pick(logic)
	if shot["uid"] != "" and logic.floor_of.has(shot["uid"]):
		shot["floor"] = logic.floor_of[shot["uid"]]
	return shot


func _start_join(logic) -> void:
	var users := _pending.duplicate()
	_pending.clear()
	_cooldown = join_cooldown_s
	var lowest := INF
	for u in users:
		lowest = minf(lowest, logic.floor_of.get(str(u["id"]), 0.0))
	shot = {"kind": "join", "floor": lowest, "uid": str(users[0]["id"]) if users.size() == 1 else "",
			"users": users, "left": join_shot_s}


func _pick(logic) -> void:
	var ranked: Array = logic.ranking()
	var hold := rng.randf_range(hold_min_s, hold_max_s)
	if ranked.is_empty() or ranked[0]["floor"] <= 0.0:
		shot = {"kind": "ground", "floor": 0.0, "uid": "", "users": [], "left": hold}
		return
	var index := 0
	var kind := "leader"
	for attempt in 3:                # try not to show the same climber twice in a row
		var r := rng.randf()
		if r < leader_weight:
			index = 0
			kind = "leader"
		elif r < leader_weight + second_weight and ranked.size() > 1:
			index = 1
			kind = "second"
		elif ranked.size() > 2:
			index = rng.randi_range(2, ranked.size() - 1)
			kind = "climber"
		else:
			index = rng.randi_range(0, ranked.size() - 1)
			kind = "leader" if index == 0 else "second"
		if str(ranked[index]["user"]["id"]) != _last_uid or ranked.size() == 1:
			break
	var user: Dictionary = ranked[index]["user"]
	_last_uid = str(user["id"])
	shot = {"kind": kind, "floor": ranked[index]["floor"], "uid": _last_uid, "users": [user], "left": hold}
