extends RefCounted
## Tug of war rules, no nodes, so they can be tested headless (tests/run_tests.gd).
## rope runs from -1.0 (team A reaches its line and wins) to +1.0 (team B wins).

const A := 0
const B := 1
const NONE := -1

# Tuning: how far each action moves the rope (1.0 = from the center to a win line).
var like_pull := 0.004           # per like, so ~250 likes win from the center
var follow_pull := 0.04
var share_boost_s := 5.0
var share_multiplier := 2.0
var gift_pull_per_diamond := 0.01
var gift_pull_cap := 0.25        # one gift never moves more than a quarter of the way

var rope := 0.0
var active := true               # false between rounds: teams can change, the rope cannot
var team_of := {}                # user_id -> A/B, kept across rounds
var players := {}                # user_id -> user dict from the event
var contribution := {}           # user_id -> rope distance pulled this round

var _boost_until := [0.0, 0.0]
var _now := 0.0


static func team_from_text(text: String) -> int:
	var t := text.strip_edges().to_upper()
	if t in ["A", "أ", "ا", "1"]:
		return A
	if t in ["B", "ب", "2"]:
		return B
	return NONE


func tick(delta: float) -> void:
	_now += delta


func new_round() -> void:
	rope = 0.0
	contribution.clear()
	_boost_until = [0.0, 0.0]
	active = true


func team_count(team: int) -> int:
	var n := 0
	for t in team_of.values():
		if t == team:
			n += 1
	return n


func boosted(team: int) -> bool:
	return _now < _boost_until[team]


func winner() -> int:
	if rope <= -1.0:
		return A
	if rope >= 1.0:
		return B
	return NONE


## Who is ahead when time runs out.
func leader() -> int:
	if rope < 0.0:
		return A
	if rope > 0.0:
		return B
	return NONE


## Top contributor of a team this round: {"user": {...}, "score": float}, or {} if nobody pulled.
func mvp(team: int) -> Dictionary:
	var best := ""
	for uid in contribution:
		if team_of.get(uid, NONE) == team and (best == "" or contribution[uid] > contribution[best]):
			best = uid
	if best == "":
		return {}
	return {"user": players[best], "score": contribution[best]}


## Applies one bridge event and returns what happened, for the screen to show:
## {"kind": "joined"|"pull"|"boost"|"gift", "team": int, "user": {...}, ...}
func handle(ev: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var user = ev.get("user")
	if not (user is Dictionary) or str(user.get("id", "")) == "":
		return out
	match ev.get("type", ""):
		"comment":
			var team := team_from_text(str(ev.get("text", "")))
			if team != NONE:
				_assign(user, team, out)
		"join":
			_ensure_team(user, out)
		"like":
			_pull(user, float(ev.get("count", 0)) * like_pull, out)
		"follow":
			_pull(user, follow_pull, out)
		"share":
			var team := _ensure_team(user, out)
			if active:
				_boost_until[team] = _now + share_boost_s
				out.append({"kind": "boost", "team": team, "user": user})
		"gift":
			var amount := minf(float(ev.get("value", 0)) * gift_pull_per_diamond, gift_pull_cap)
			var team := _pull(user, amount, out)
			out.append({"kind": "gift", "team": team, "user": user,
					"gift": ev.get("gift", {}), "count": int(ev.get("count", 1))})
	return out


func _assign(user: Dictionary, team: int, out: Array[Dictionary]) -> void:
	var uid := str(user["id"])
	var before: int = team_of.get(uid, NONE)
	players[uid] = user
	if before == team:
		return
	team_of[uid] = team
	out.append({"kind": "joined", "team": team, "user": user, "switched": before != NONE})


## Puts a viewer without a team on the smaller team, so any interaction counts.
func _ensure_team(user: Dictionary, out: Array[Dictionary]) -> int:
	var uid := str(user["id"])
	if team_of.has(uid):
		players[uid] = user
		return team_of[uid]
	var team := A if team_count(A) <= team_count(B) else B
	_assign(user, team, out)
	return team


func _pull(user: Dictionary, amount: float, out: Array[Dictionary]) -> int:
	var team := _ensure_team(user, out)
	if not active or amount <= 0.0:
		return team
	if boosted(team):
		amount *= share_multiplier
	var direction := -1.0 if team == A else 1.0
	rope = clampf(rope + direction * amount, -1.0, 1.0)
	var uid := str(user["id"])
	contribution[uid] = contribution.get(uid, 0.0) + amount
	out.append({"kind": "pull", "team": team, "user": user, "amount": amount})
	return team
