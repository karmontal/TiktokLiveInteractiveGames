extends RefCounted
## Tower climb rules, no nodes, so they can be tested headless (tests/run_tests.gd).
## Every viewer who comments or enters the LIVE gets a climber on floor 0. Likes, follows,
## shares and gifts move them up; falling rocks knock climbers in their band back down.
## The first to reach top_floor wins the round; if time runs out, the highest climber wins.
## Rounds loop by themselves: climb -> result -> climb ...

# Tuning (floors are floats; the screen shows whole floors)
var top_floor := 100.0
var round_s := 300.0
var result_s := 12.0
var like_floors := 0.2           # per like, so ~500 likes reach the top alone
var follow_floors := 1.0         # and a checkpoint: rocks never drop you below it
var share_floors := 2.0          # and wings: the next rock that hits you misses
var gift_floors_per_diamond := 1.0
var gift_floors_cap := 12.0      # one gift never lifts more than this
var big_gift_everyone := 3.0     # a large gift also lifts every other climber
var hazard_every_min := 9.0
var hazard_every_max := 14.0
var hazard_warning_s := 2.5      # the band shows on screen before the rocks fall
var hazard_band := 12.0          # floors covered by one rock fall
var hazard_drop := 6.0

var rng := RandomNumberGenerator.new()

# Live state, read by the screen
var phase := "climb"             # climb | result
var time_left := 0.0
var round_no := 0
var players := {}                # user_id -> user dict (kept across rounds)
var floor_of := {}               # user_id -> floor this round
var checkpoint := {}             # user_id -> lowest floor a rock can drop you to
var wings := {}                  # user_id -> true while protected
var hazard := {}                 # {"from", "to", "in"} while a rock fall is announced
var winner := {}                 # {"user", "floor", "top": bool} of the last round
var wins := {}                   # user_id -> rounds won this stream

var _next_hazard := 0.0


## Starts the first round. Returns the effects for the screen.
func start() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_new_round(out)
	return out


func tick(delta: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	time_left -= delta
	if phase == "result":
		if time_left <= 0.0:
			_new_round(out)
		return out
	if time_left <= 0.0:
		_end_round(out)
		return out
	if hazard.is_empty():
		_next_hazard -= delta
		if _next_hazard <= 0.0:
			_announce_hazard(out)
	else:
		hazard["in"] -= delta
		if hazard["in"] <= 0.0:
			_strike(out)
	return out


## Applies one bridge event:
## {"kind": "joined"|"climb"|"checkpoint"|"wings"|"gift"|"lift_all"|"summit"|"round_end", ...}
func handle(ev: Dictionary) -> Array[Dictionary]:
	if ev.get("type", "") == "stream_end":
		return reset_stream()
	var out: Array[Dictionary] = []
	var user = ev.get("user")
	if not (user is Dictionary) or str(user.get("id", "")) == "":
		return out
	var uid := _ensure(user, out)
	match ev.get("type", ""):
		"like":
			_climb(uid, float(ev.get("count", 0)) * like_floors, out)
		"follow":
			_climb(uid, follow_floors, out)
			if phase == "climb":
				checkpoint[uid] = floorf(floor_of[uid])
				out.append({"kind": "checkpoint", "user": user, "floor": checkpoint[uid]})
		"share":
			if phase == "climb":
				wings[uid] = true
				out.append({"kind": "wings", "user": user})
			_climb(uid, share_floors, out)
		"gift":
			var gift: Dictionary = ev.get("gift", {})
			var amount := minf(float(ev.get("value", 0)) * gift_floors_per_diamond, gift_floors_cap)
			out.append({"kind": "gift", "user": user, "gift": gift, "count": int(ev.get("count", 1)),
					"floors": amount})
			if gift.get("tier", "") == "large" and phase == "climb":
				out.append({"kind": "lift_all", "user": user, "floors": big_gift_everyone})
				for other in floor_of.keys():
					if other != uid and phase == "climb":
						_climb(other, big_gift_everyone, out)
			_climb(uid, amount, out)
	return out


## Highest climbers first: [{"user", "floor"}].
func ranking(limit := 0) -> Array[Dictionary]:
	var ids := floor_of.keys()
	ids.sort_custom(func(a, b): return floor_of[a] > floor_of[b] or (floor_of[a] == floor_of[b] and a < b))
	var out: Array[Dictionary] = []
	for uid in ids:
		if limit > 0 and out.size() >= limit:
			break
		out.append({"user": players[uid], "floor": floor_of[uid]})
	return out


## Most round wins this stream: [{"user", "wins"}].
func hall_of_fame(limit := 3) -> Array[Dictionary]:
	var ids := wins.keys()
	ids.sort_custom(func(a, b): return wins[a] > wins[b] or (wins[a] == wins[b] and a < b))
	var out: Array[Dictionary] = []
	for uid in ids.slice(0, limit):
		out.append({"user": players[uid], "wins": wins[uid]})
	return out


func leader_floor() -> float:
	var best := 0.0
	for f in floor_of.values():
		best = maxf(best, f)
	return best


## A new stream: forget everyone, including the hall of fame.
func reset_stream() -> Array[Dictionary]:
	players.clear()
	wins.clear()
	floor_of.clear()
	checkpoint.clear()
	winner = {}
	round_no = 0
	return start()


# ---------------------------------------------------------------- internals

func _ensure(user: Dictionary, out: Array[Dictionary]) -> String:
	var uid := str(user["id"])
	players[uid] = user
	if not floor_of.has(uid):
		floor_of[uid] = 0.0
		checkpoint[uid] = 0.0
		out.append({"kind": "joined", "user": user})
	return uid


func _climb(uid: String, amount: float, out: Array[Dictionary]) -> void:
	if phase != "climb" or amount <= 0.0:
		return
	var from: float = floor_of[uid]
	floor_of[uid] = minf(top_floor, from + amount)
	out.append({"kind": "climb", "user": players[uid], "from": from, "to": floor_of[uid]})
	if floor_of[uid] >= top_floor:
		out.append({"kind": "summit", "user": players[uid]})
		_end_round(out)


func _announce_hazard(out: Array[Dictionary]) -> void:
	_next_hazard = rng.randf_range(hazard_every_min, hazard_every_max)
	var targets := []
	for uid in floor_of:
		if floor_of[uid] >= hazard_drop:     # nobody near the ground is worth a rock
			targets.append(uid)
	if targets.is_empty():
		return
	var center: float = floor_of[targets[rng.randi_range(0, targets.size() - 1)]]
	var from := clampf(center - rng.randf_range(0.2, 0.8) * hazard_band, 1.0, top_floor - hazard_band)
	hazard = {"from": from, "to": from + hazard_band, "in": hazard_warning_s}
	out.append({"kind": "hazard_warning", "from": hazard["from"], "to": hazard["to"]})


func _strike(out: Array[Dictionary]) -> void:
	var fell: Array[Dictionary] = []
	var saved: Array[Dictionary] = []
	for uid in floor_of:
		var f: float = floor_of[uid]
		if f < hazard["from"] or f > hazard["to"]:
			continue
		if wings.has(uid):
			wings.erase(uid)
			saved.append({"user": players[uid]})
			continue
		floor_of[uid] = maxf(checkpoint[uid], f - hazard_drop)
		if floor_of[uid] < f:
			fell.append({"user": players[uid], "from": f, "to": floor_of[uid]})
	out.append({"kind": "hazard_strike", "from": hazard["from"], "to": hazard["to"],
			"fell": fell, "saved": saved})
	hazard = {}


func _end_round(out: Array[Dictionary]) -> void:
	phase = "result"
	time_left = result_s
	hazard = {}
	var top := ranking(5)
	winner = {}
	if not top.is_empty() and top[0]["floor"] > 0.0:
		var uid := str(top[0]["user"]["id"])
		wins[uid] = wins.get(uid, 0) + 1
		winner = {"user": top[0]["user"], "floor": top[0]["floor"], "top": top[0]["floor"] >= top_floor}
	out.append({"kind": "round_end", "winner": winner, "top": top, "hall": hall_of_fame()})


func _new_round(out: Array[Dictionary]) -> void:
	round_no += 1
	phase = "climb"
	time_left = round_s
	hazard = {}
	wings.clear()
	for uid in floor_of:
		floor_of[uid] = 0.0
		checkpoint[uid] = 0.0
	_next_hazard = rng.randf_range(hazard_every_min, hazard_every_max)
	out.append({"kind": "round_start", "round": round_no})
