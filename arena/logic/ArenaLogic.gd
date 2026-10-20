extends RefCounted
## Arena brawl rules, no nodes, so they can be tested headless (tests/run_tests.gd).
## Everyone fights everyone on a round island seen from above: positions are Vector2 (x, z).
## Fighters walk to the nearest rival and punch by themselves; viewers power them up.
## A punch adds damage and knocks the target back, harder the more damage it has taken.
## Off the edge = knocked out, and the KO goes to the last fighter who hit them.
## Every minute the outer ring breaks away. The last one standing wins once they have been
## alone on the island for alone_s (a newcomer dropping in breaks it); at 5:00, the most KOs.
## Rounds loop by themselves: lobby (drop in, nobody fights) -> fight -> result -> lobby ...
## Every round starts with the host's bots (set_host) so the island is never empty.

# Round and island
var lobby_s := 30.0                     # dropping in before the fight
var min_players := 2                    # the lobby waits for this many
var alone_s := 30.0                     # the last one standing must stay alone this long
var round_s := 300.0
var result_s := 14.0
var radii := [9.0, 7.5, 6.0, 4.5, 3.0]   # island radius after 0, 1, 2, 3, 4 collapses
var collapse_every := 60.0
var warn_s := 10.0
var max_fighters := 40
var bot_count := 3                      # house fighters named after the host, every round
var join_likes := 5                     # likes it takes to drop in (any comment, follow, share or gift: at once)
var recent_s := 600.0                   # who is brought back for the next round
# Fighting
var drop_s := 1.0                       # falling in from the sky, untouchable
var walk_speed := 2.6
var reach := 1.25
var cooldown_min := 1.0
var cooldown_max := 1.7
var punch_damage := 6.0
var knock_base := 1.6
var knock_per_damage := 0.028
var friction := 4.5
var ko_credit_s := 4.0
# Interactions
var like_power := 0.02                  # per like: +2% knockback, up to max_power
var max_power := 1.0
var power_decay := 0.1                  # per second
var dash_speed := 13.0
var dash_s := 0.45
var dash_mult := 1.6
var hammer_s := 15.0
var hammer_mult := 2.0
var giant_s := 10.0
var giant_size := 2.4
var giant_mult := 2.2
var giant_resist := 0.25                # giants take a quarter of the knockback
var shockwave_radius := 4.0
var shockwave_push := 9.0

var rng := RandomNumberGenerator.new()

# Live state, read by the screen
var phase := "lobby"                    # lobby | fight | result
var time_left := 0.0
var round_no := 0
var stage := 0                          # collapses done this round
var warning := -1.0                     # seconds until the next collapse while it is announced
var alone := -1.0                       # seconds the last fighter still has to hold out
var fighters := {}                      # uid -> fighter dict (this round, alive or out)
var winner := {}

# This stream
var players := {}                       # uid -> user
var last_seen := {}                     # uid -> clock
var wins := {}                          # uid -> rounds won
var total_kos := {}                     # uid -> KOs this stream
var bots: Array[Dictionary] = []        # the host's fighters (users with "bot": true)
var likes_waiting := {}                 # uid -> likes from viewers not in yet

var _clock := 0.0


func start() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_new_round(out)
	return out


## Names the house fighters after the host: "<host> 1", "<host> 2", ...
func set_host(host: String) -> void:
	bots.clear()
	for i in bot_count:
		bots.append({"id": "bot:%d" % (i + 1), "name": "%s %d" % [host, i + 1], "avatar": "", "bot": true})


func is_bot(uid: String) -> bool:
	return uid.begins_with("bot:")


func radius() -> float:
	return radii[mini(stage, radii.size() - 1)]


func next_radius() -> float:
	return radii[mini(stage + 1, radii.size() - 1)]


func elapsed() -> float:
	return round_s - time_left


func alive_ids() -> Array:
	return fighters.keys().filter(func(uid): return fighters[uid]["alive"])


func size_of(f: Dictionary) -> float:
	return giant_size if f["giant"] > 0.0 else 1.0


## Most KOs first, the ones still standing ahead on a tie: [{"user", "kos", "alive"}].
func ranking(limit := 0) -> Array[Dictionary]:
	var ids := fighters.keys()
	ids.sort_custom(func(a, b):
		var fa: Dictionary = fighters[a]
		var fb: Dictionary = fighters[b]
		if fa["kos"] != fb["kos"]:
			return fa["kos"] > fb["kos"]
		if fa["alive"] != fb["alive"]:
			return fa["alive"]
		return a < b)
	var out: Array[Dictionary] = []
	for uid in ids:
		if limit > 0 and out.size() >= limit:
			break
		var f: Dictionary = fighters[uid]
		out.append({"user": f["user"], "kos": f["kos"], "alive": f["alive"]})
	return out


## Most rounds won this stream, then most KOs: [{"user", "wins", "kos"}].
func hall_of_fame(limit := 3) -> Array[Dictionary]:
	var ids := wins.keys()
	ids.sort_custom(func(a, b):
		if wins[a] != wins[b]:
			return wins[a] > wins[b]
		return total_kos.get(a, 0) > total_kos.get(b, 0))
	var out: Array[Dictionary] = []
	for uid in ids.slice(0, limit):
		out.append({"user": players[uid], "wins": wins[uid], "kos": total_kos.get(uid, 0)})
	return out


func reset_stream() -> Array[Dictionary]:
	players.clear()
	last_seen.clear()
	wins.clear()
	total_kos.clear()
	likes_waiting.clear()
	fighters.clear()
	round_no = 0
	return start()


# ---------------------------------------------------------------- time

func tick(delta: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_clock += delta
	time_left -= delta
	if phase == "result":
		if time_left <= 0.0:
			_new_round(out)
		return out
	if phase == "lobby":
		for uid in alive_ids():
			fighters[uid]["drop"] = maxf(0.0, fighters[uid]["drop"] - delta)
		if time_left <= 0.0:
			time_left = 0.0                  # keeps waiting until enough players
			if alive_ids().size() >= min_players:
				begin_fight(out)
		return out
	_collapse_clock(out)
	for uid in alive_ids():
		_step(fighters[uid], delta, out)
	_separate()
	for uid in alive_ids():
		var f: Dictionary = fighters[uid]
		if f["pos"].length() > radius():
			_knock_out(f, out)
	var alive := alive_ids()
	if alive.size() == 1 and fighters.size() >= 2:
		if alone < 0.0:
			alone = alone_s
			out.append({"kind": "alone", "user": fighters[alive[0]]["user"], "seconds": alone_s})
		alone = maxf(0.0, alone - delta)
	elif alone >= 0.0:
		alone = -1.0
		out.append({"kind": "alone_broken"})
	if alive.is_empty() or alone == 0.0 or time_left <= 0.0:
		_end_round(out)
	return out


## Ends the lobby: the clock starts and fighters go for each other.
func begin_fight(out: Array[Dictionary] = []) -> void:
	phase = "fight"
	time_left = round_s
	alone = -1.0
	for uid in alive_ids():
		fighters[uid]["drop"] = 0.0
	out.append({"kind": "fight_start", "fighters": alive_ids().size()})


func _collapse_clock(out: Array[Dictionary]) -> void:
	if stage + 1 >= radii.size():
		warning = -1.0
		return
	var at := collapse_every * (stage + 1)
	if elapsed() >= at - warn_s:
		if warning < 0.0:
			out.append({"kind": "warning", "stage": stage + 1, "radius": next_radius()})
		warning = maxf(0.0, at - elapsed())
	if elapsed() >= at:
		stage += 1
		warning = -1.0
		out.append({"kind": "collapse", "stage": stage, "radius": radius()})


func _step(f: Dictionary, delta: float, out: Array[Dictionary]) -> void:
	for key in ["cooldown", "drop", "dash", "hammer", "giant", "punched", "hurt"]:
		var before: float = f[key]
		f[key] = maxf(0.0, before - delta)
		if before > 0.0 and f[key] == 0.0:
			if key == "giant":
				out.append({"kind": "giant_off", "user": f["user"]})
			elif key == "hammer":
				out.append({"kind": "hammer_off", "user": f["user"]})
	f["power"] = maxf(0.0, f["power"] - power_decay * delta)
	if f["drop"] > 0.0:
		return
	var pos: Vector2 = f["pos"]
	if f["dash"] > 0.0:
		pos += f["dash_dir"] * dash_speed * delta
		for uid in alive_ids():
			var t: Dictionary = fighters[uid]
			if t == f or f["dash_hits"].has(uid) or t["drop"] > 0.0:
				continue
			if pos.distance_to(t["pos"]) < 0.9 * (size_of(f) + size_of(t)) * 0.6:
				f["dash_hits"][uid] = true
				_punch(f, t, dash_mult, out)
	else:
		var t := _nearest(f)
		var to_center: Vector2 = -pos
		if t.is_empty():
			if pos.length() > 0.5:                     # wander back to the middle, never past it
				pos += to_center.normalized() * minf(walk_speed * 0.5 * delta, pos.length() - 0.5)
		else:
			var gap: Vector2 = t["pos"] - pos
			f["target"] = str(t["user"]["id"])
			if gap.length() > reach * (size_of(f) + size_of(t)) * 0.5 + 0.3:
				var move := gap.normalized() * walk_speed
				if pos.length() > radius() - 1.2:          # do not walk off by yourself
					move += to_center.normalized() * walk_speed * 0.8
				pos += move * delta
				f["facing"] = gap.normalized()
			elif f["cooldown"] <= 0.0:
				f["facing"] = gap.normalized()
				_punch(f, t, 1.0, out)
	pos += f["vel"] * delta
	f["vel"] *= exp(-friction * delta)
	f["pos"] = pos


func _nearest(f: Dictionary) -> Dictionary:
	var best := {}
	var best_d := INF
	for uid in alive_ids():
		var t: Dictionary = fighters[uid]
		if t == f or t["drop"] > 0.0:
			continue
		var d: float = f["pos"].distance_squared_to(t["pos"])
		if d < best_d:
			best_d = d
			best = t
	return best


## Keeps fighters from standing inside each other.
func _separate() -> void:
	var ids := alive_ids()
	for i in ids.size():
		var a: Dictionary = fighters[ids[i]]
		for j in range(i + 1, ids.size()):
			var b: Dictionary = fighters[ids[j]]
			var gap: Vector2 = b["pos"] - a["pos"]
			var need := 0.45 * (size_of(a) + size_of(b))
			var d := gap.length()
			if d < need and d > 0.0001:
				var push := gap / d * (need - d) * 0.5
				a["pos"] -= push
				b["pos"] += push


func _punch(a: Dictionary, t: Dictionary, extra: float, out: Array[Dictionary]) -> void:
	a["cooldown"] = rng.randf_range(cooldown_min, cooldown_max)
	a["punched"] = 0.35
	var dir: Vector2 = t["pos"] - a["pos"]
	dir = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT.rotated(rng.randf() * TAU)
	if t["shield"]:
		t["shield"] = false
		t["vel"] += dir * 1.5
		out.append({"kind": "shield_break", "user": t["user"], "by": a["user"]})
		return
	var mult: float = (1.0 + a["power"]) * extra
	if a["hammer"] > 0.0:
		mult *= hammer_mult
	if a["giant"] > 0.0:
		mult *= giant_mult
	t["damage"] += punch_damage * (1.5 if a["hammer"] > 0.0 or a["giant"] > 0.0 else 1.0)
	var push: float = (knock_base + t["damage"] * knock_per_damage) * mult
	if t["giant"] > 0.0:
		push *= giant_resist
	t["vel"] += dir * push
	t["hurt"] = 0.3
	t["last_hitter"] = str(a["user"]["id"])
	t["last_hit_at"] = _clock
	out.append({"kind": "punch", "by": a["user"], "target": t["user"], "push": push, "pos": t["pos"]})


func _knock_out(f: Dictionary, out: Array[Dictionary]) -> void:
	f["alive"] = false
	var by := {}
	var hitter: String = f["last_hitter"]
	if hitter != "" and _clock - f["last_hit_at"] <= ko_credit_s and fighters.has(hitter):
		fighters[hitter]["kos"] += 1
		by = fighters[hitter]["user"]
	out.append({"kind": "ko", "user": f["user"], "by": by, "pos": f["pos"], "vel": f["vel"]})


# ---------------------------------------------------------------- viewers

func handle(ev: Dictionary) -> Array[Dictionary]:
	if ev.get("type", "") == "stream_end":
		return reset_stream()
	var out: Array[Dictionary] = []
	var user = ev.get("user")
	if not (user is Dictionary) or str(user.get("id", "")) == "":
		return out
	var uid := str(user["id"])
	if is_bot(uid):
		return out
	if ev.get("type", "") == "like" and not fighters.has(uid) and not players.has(uid):
		likes_waiting[uid] = likes_waiting.get(uid, 0) + int(ev.get("count", 0))
		if likes_waiting[uid] < join_likes:
			return out                   # a few more likes to drop in
		ev = ev.duplicate()
		ev["count"] = likes_waiting[uid]
		likes_waiting.erase(uid)
	players[uid] = user
	last_seen[uid] = _clock
	if phase == "result":
		return out                       # they fight from the next round
	if not fighters.has(uid):
		if alive_ids().size() >= max_fighters:
			return out
		_spawn(user, out)
	var f: Dictionary = fighters[uid]
	f["user"] = user
	if not f["alive"]:
		return out                       # knocked out: wait for the next round
	match ev.get("type", ""):
		"like":
			f["power"] = minf(max_power, f["power"] + float(ev.get("count", 0)) * like_power)
			out.append({"kind": "power", "user": user, "power": f["power"]})
		"follow":
			f["shield"] = true
			out.append({"kind": "shield", "user": user})
		"share":
			if phase == "lobby":
				return out                   # nothing to dash at yet
			var t := _nearest(f)
			var dir: Vector2 = (t["pos"] - f["pos"]).normalized() if not t.is_empty() else -f["pos"].normalized()
			f["dash"] = dash_s
			f["dash_dir"] = dir if dir.length() > 0.001 else Vector2.RIGHT
			f["dash_hits"] = {}
			f["facing"] = f["dash_dir"]
			out.append({"kind": "dash", "user": user})
		"gift":
			var gift: Dictionary = ev.get("gift", {})
			f["gifts"] += int(ev.get("count", 1))
			match gift.get("tier", "small"):
				"large":
					f["giant"] = giant_s
					out.append({"kind": "giant", "user": user, "gift": gift})
					if phase == "fight":
						_shockwave(f, out)
				"medium":
					f["hammer"] = hammer_s
					out.append({"kind": "hammer", "user": user, "gift": gift})
				_:
					f["damage"] = 0.0
					out.append({"kind": "heal", "user": user, "gift": gift})
	return out


func _shockwave(f: Dictionary, out: Array[Dictionary]) -> void:
	var hit := 0
	for uid in alive_ids():
		var t: Dictionary = fighters[uid]
		if t == f or t["drop"] > 0.0:
			continue
		var gap: Vector2 = t["pos"] - f["pos"]
		if gap.length() < shockwave_radius:
			var dir := gap.normalized() if gap.length() > 0.001 else Vector2.RIGHT.rotated(rng.randf() * TAU)
			t["vel"] += dir * shockwave_push * (1.0 - gap.length() / shockwave_radius * 0.5)
			t["hurt"] = 0.3
			t["last_hitter"] = str(f["user"]["id"])
			t["last_hit_at"] = _clock
			hit += 1
	out.append({"kind": "shockwave", "user": f["user"], "pos": f["pos"], "hit": hit})


# ---------------------------------------------------------------- rounds

func _spawn(user: Dictionary, out: Array[Dictionary]) -> void:
	var uid := str(user["id"])
	var pos := Vector2.ZERO
	for attempt in 6:                    # somewhere not on top of someone
		pos = Vector2.RIGHT.rotated(rng.randf() * TAU) * sqrt(rng.randf()) * radius() * 0.7
		var clear := true
		for other in alive_ids():
			if fighters[other]["pos"].distance_to(pos) < 1.2:
				clear = false
				break
		if clear:
			break
	fighters[uid] = {"user": user, "pos": pos, "vel": Vector2.ZERO,
			"facing": -pos.normalized() if pos.length() > 0.01 else Vector2.DOWN,
			"damage": 0.0, "power": 0.0, "shield": false, "hammer": 0.0, "giant": 0.0, "dash": 0.0,
			"dash_dir": Vector2.RIGHT, "dash_hits": {}, "cooldown": rng.randf_range(0.2, 0.8),
			"drop": drop_s, "punched": 0.0, "hurt": 0.0, "alive": true, "last_hitter": "", "last_hit_at": -INF,
			"kos": 0, "gifts": 0, "target": ""}
	out.append({"kind": "joined", "user": user, "pos": pos})


func _end_round(out: Array[Dictionary]) -> void:
	phase = "result"
	time_left = result_s
	warning = -1.0
	alone = -1.0
	var alive := alive_ids()
	var pool: Array = alive if not alive.is_empty() else fighters.keys()
	var best := ""
	for uid in pool:
		var f: Dictionary = fighters[uid]
		if best == "":
			best = uid
			continue
		var b: Dictionary = fighters[best]
		if f["kos"] > b["kos"] or (f["kos"] == b["kos"] and f["damage"] < b["damage"]):
			best = uid
	for uid in fighters:
		if not is_bot(uid):
			total_kos[uid] = total_kos.get(uid, 0) + fighters[uid]["kos"]
	winner = {}
	if best != "" and (fighters.size() >= 2 or fighters[best]["kos"] > 0):
		var w: Dictionary = fighters[best]
		if not is_bot(best):
			wins[best] = wins.get(best, 0) + 1
		winner = {"user": w["user"], "kos": w["kos"], "gifts": w["gifts"], "survived": w["alive"],
				"last_standing": alive.size() == 1}
	out.append({"kind": "round_end", "winner": winner, "top": ranking(5), "hall": hall_of_fame()})


func _new_round(out: Array[Dictionary]) -> void:
	round_no += 1
	phase = "lobby"
	time_left = lobby_s
	stage = 0
	warning = -1.0
	alone = -1.0
	fighters.clear()
	var back := last_seen.keys().filter(func(uid): return _clock - last_seen[uid] <= recent_s)
	back.sort_custom(func(a, b): return last_seen[a] > last_seen[b])     # most recent first
	var spawned: Array[Dictionary] = []
	for bot in bots:
		_spawn(bot, spawned)
	for uid in back.slice(0, max_fighters - bots.size()):
		_spawn(players[uid], spawned)
	out.append({"kind": "round_start", "round": round_no, "fighters": spawned.size(), "lobby": lobby_s})
