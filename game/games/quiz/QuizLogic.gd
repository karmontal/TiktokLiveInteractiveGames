extends RefCounted
## Quiz rules, no nodes, so they can be tested headless (tests/run_tests.gd).
## Phases loop by themselves for the whole stream:
## intermission -> (question -> reveal) x questions_per_round -> board -> intermission ...

const LETTERS := ["A", "B", "C", "D"]
const BOT_PREFIX := "bot:"

# Timing (seconds)
var intermission_s := 15.0
var question_s := 15.0
var reveal_s := 6.0
var board_s := 12.0
var questions_per_round := 10
var max_categories := 4          # each round picks 1..max_categories at random

# Scoring and interactions
var base_points := 100
var speed_points := 100          # extra for answering at once, 0 at the deadline
var likes_per_removal := 50
var max_removed := 2             # always leave the right answer and one wrong one
var small_gift_seconds := 3.0
var big_gift_seconds := 10.0
var max_extra_seconds := 20.0    # per question, all gifts together

# Filler players: they answer (so the percentages move) but never score or rank.
# Each real viewer who answered the last question takes one bot's place.
var bots_min := 5
var bots_max := 10
var bot_accuracy := 0.4

var rng := RandomNumberGenerator.new()

# Live state, read by the screen
var phase := "idle"              # intermission | question | reveal | board
var time_left := 0.0
var phase_length := 1.0
var round_categories: Array = []
var round_questions: Array = []
var question_index := -1         # within the round
var current := {}                # {"text", "options": [4], "answer": int, "category"}
var counts := [0, 0, 0, 0]
var removed: Array = []
var likes_bucket := 0
var answers := {}                # user_id -> {"choice": int, "t": seconds after the question appeared}
var last_champion := {}          # {"user", "score"} of the round before

# This stream (cleared by reset_stream)
var players := {}                # user_id -> user dict
var score := {}                  # user_id -> points
var correct := {}                # user_id -> right answers
var round_score := {}            # user_id -> points this round
var multiplier := {}             # user_id -> 2 or 3, for their next right answer
var change_tokens := {}          # user_id -> answers they may still change (from follows)

var _by_category := {}           # category -> Array of question dicts
var _used := {}                  # question text -> true
var _elapsed := 0.0
var _extra := 0.0
var _bots: Array = []            # [{"id", "at", "choice"}] still to answer
var _last_real_answered := 0


static func parse_choice(text: String) -> int:
	var t := text.strip_edges().to_upper()
	if t in ["A", "أ", "ا", "1", "١"]:
		return 0
	if t in ["B", "ب", "2", "٢"]:
		return 1
	if t in ["C", "ج", "3", "٣"]:
		return 2
	if t in ["D", "د", "4", "٤"]:
		return 3
	return -1


static func is_bot(uid: String) -> bool:
	return uid.begins_with(BOT_PREFIX)


## Questions as in the pack files: {"q", "options": [right, wrong, wrong, wrong], "category"}.
func load_questions(list: Array) -> void:
	_by_category.clear()
	for q in list:
		if q is Dictionary and q.get("options", []).size() == 4 and str(q.get("q", "")) != "":
			var cat := str(q.get("category", "عام"))
			if not _by_category.has(cat):
				_by_category[cat] = []
			_by_category[cat].append(q)


func categories() -> Array:
	return _by_category.keys()


func start() -> Array[Dictionary]:
	reset_stream()
	var out: Array[Dictionary] = []
	_enter_intermission(out)
	return out


## A new stream starts with an empty leaderboard.
func reset_stream() -> void:
	players.clear()
	score.clear()
	correct.clear()
	round_score.clear()
	multiplier.clear()
	change_tokens.clear()
	_used.clear()
	last_champion = {}
	_last_real_answered = 0


func answered_count() -> int:
	return answers.size()


func right_count() -> int:
	var n := 0
	for uid in answers:
		if answers[uid]["choice"] == current.get("answer", -1):
			n += 1
	return n


## Best players of this stream: [{"user", "score", "correct"}], highest first.
func top(n: int) -> Array:
	return _ranked(score, n)


func tick(delta: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if phase == "idle":
		return out
	time_left -= delta
	if phase == "question":
		_elapsed += delta
		_run_bots(out)
	if time_left > 0.0:
		return out
	match phase:
		"intermission":
			_enter_question(out)
		"question":
			_reveal(out)
		"reveal":
			if question_index + 1 < round_questions.size():
				_enter_question(out)
			else:
				_enter_board(out)
		"board":
			_enter_intermission(out)
	return out


## Applies one bridge event. Returns what happened, for the screen:
## {"kind": "answer"|"changed"|"removed"|"multiplier"|"joker"|"gift", ...}
func handle(ev: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ev.get("type", "") == "stream_end":
		reset_stream()
		return out
	var user = ev.get("user")
	if not (user is Dictionary) or str(user.get("id", "")) == "":
		return out
	var uid := str(user["id"])
	players[uid] = user
	match ev.get("type", ""):
		"comment":
			var choice := parse_choice(str(ev.get("text", "")))
			if choice >= 0:
				_answer(uid, choice, out)
		"like":
			_add_likes(int(ev.get("count", 0)), out)
		"follow":
			change_tokens[uid] = change_tokens.get(uid, 0) + 1
			out.append({"kind": "joker", "user": user})
		"share":
			_boost(uid, 2, "share", out)
		"gift":
			var gift: Dictionary = ev.get("gift", {})
			var tier := str(gift.get("tier", "small"))
			var seconds := 0.0
			match tier:
				"large":
					seconds = _add_time(big_gift_seconds)
					_boost(uid, 3, "gift", out)
				"medium":
					_remove_wrong(user, out)
					_boost(uid, 2, "gift", out)
				_:
					seconds = _add_time(small_gift_seconds)
					_boost(uid, 2, "gift", out)
			out.append({"kind": "gift", "user": user, "gift": gift, "tier": tier,
					"count": int(ev.get("count", 1)), "seconds": seconds})
	return out


# ---------------------------------------------------------------- phases

func _set_phase(name: String, seconds: float) -> void:
	phase = name
	time_left = seconds
	phase_length = seconds


func _enter_intermission(out: Array[Dictionary]) -> void:
	round_score.clear()
	_pick_round()
	question_index = -1
	_set_phase("intermission", intermission_s)
	out.append({"kind": "intermission", "categories": round_categories, "champion": last_champion})


func _pick_round() -> void:
	var cats := _shuffled(categories())
	var k := rng.randi_range(1, mini(max_categories, cats.size())) if cats.size() > 0 else 0
	round_categories = cats.slice(0, k)
	var fresh := []
	var seen := []
	for c in round_categories:
		for q in _by_category[c]:
			(seen if _used.has(q["q"]) else fresh).append(q)
	var pool := _shuffled(fresh) + _shuffled(seen)
	if pool.size() < questions_per_round:      # small categories: borrow from the others
		var others := []
		for c in cats.slice(k):
			others.append_array(_by_category[c])
		pool.append_array(_shuffled(others))
	round_questions = pool.slice(0, questions_per_round)


func _enter_question(out: Array[Dictionary]) -> void:
	question_index += 1
	if question_index >= round_questions.size():
		_enter_board(out)
		return
	var q: Dictionary = round_questions[question_index]
	_used[q["q"]] = true
	var order := _shuffled([0, 1, 2, 3])
	var options := []
	for i in order:
		options.append(str(q["options"][i]))
	current = {"text": str(q["q"]), "options": options, "answer": order.find(0),
			"category": str(q.get("category", ""))}
	counts = [0, 0, 0, 0]
	removed = []
	likes_bucket = 0
	answers.clear()
	_elapsed = 0.0
	_extra = 0.0
	_set_phase("question", question_s)
	_plan_bots()
	out.append({"kind": "question", "index": question_index, "total": round_questions.size(),
			"text": current["text"], "options": options, "category": current["category"]})


func _reveal(out: Array[Dictionary]) -> void:
	_set_phase("reveal", reveal_s)
	var winners := []
	var real := 0
	for uid in answers:
		if is_bot(uid):
			continue
		real += 1
		var a: Dictionary = answers[uid]
		if a["choice"] != current["answer"]:
			continue
		var speed := clampf(1.0 - a["t"] / question_s, 0.0, 1.0)
		var mult: int = multiplier.get(uid, 1)
		multiplier.erase(uid)
		var points := int(round((base_points + speed_points * speed) * mult))
		score[uid] = score.get(uid, 0) + points
		round_score[uid] = round_score.get(uid, 0) + points
		correct[uid] = correct.get(uid, 0) + 1
		winners.append({"user": players[uid], "points": points, "time": a["t"], "multiplier": mult})
	winners.sort_custom(func(x, y): return x["time"] < y["time"])
	_last_real_answered = real
	out.append({"kind": "reveal", "answer": current["answer"], "fastest": winners.slice(0, 3),
			"right": right_count(), "answered": answered_count(),
			"boosted": winners.filter(func(w): return w["multiplier"] > 1)})


func _enter_board(out: Array[Dictionary]) -> void:
	var best := _ranked(round_score, 1)
	last_champion = best[0] if best.size() > 0 else {}
	_set_phase("board", board_s)
	out.append({"kind": "board", "top": top(10)})


# ---------------------------------------------------------------- actions

func _answer(uid: String, choice: int, out: Array[Dictionary]) -> void:
	if phase != "question" or choice in removed:
		return
	if not answers.has(uid):
		answers[uid] = {"choice": choice, "t": _elapsed}
		counts[choice] += 1
		out.append({"kind": "answer", "choice": choice})
	elif change_tokens.get(uid, 0) > 0 and answers[uid]["choice"] != choice:
		counts[answers[uid]["choice"]] -= 1
		counts[choice] += 1
		answers[uid] = {"choice": choice, "t": _elapsed}
		change_tokens[uid] -= 1
		out.append({"kind": "changed", "user": players.get(uid, {}), "choice": choice})


func _add_likes(count: int, out: Array[Dictionary]) -> void:
	if phase != "question" or count <= 0:
		return
	likes_bucket += count
	while likes_bucket >= likes_per_removal and removed.size() < max_removed:
		likes_bucket -= likes_per_removal
		_remove_wrong({}, out)
	if removed.size() >= max_removed:
		likes_bucket = 0


## Removes one random wrong option for everyone. `by` is {} for likes, else the gift sender.
func _remove_wrong(by: Dictionary, out: Array[Dictionary]) -> bool:
	if phase != "question" or removed.size() >= max_removed:
		return false
	var wrong := []
	for i in 4:
		if i != current["answer"] and not (i in removed):
			wrong.append(i)
	var option: int = wrong[rng.randi_range(0, wrong.size() - 1)]
	removed.append(option)
	out.append({"kind": "removed", "option": option, "by": by})
	return true


func _add_time(seconds: float) -> float:
	if phase != "question":
		return 0.0
	var add := minf(seconds, max_extra_seconds - _extra)
	if add <= 0.0:
		return 0.0
	_extra += add
	time_left += add
	phase_length += add
	return add


func _boost(uid: String, x: int, source: String, out: Array[Dictionary]) -> void:
	multiplier[uid] = maxi(multiplier.get(uid, 1), x)
	out.append({"kind": "multiplier", "user": players[uid], "x": multiplier[uid], "source": source})


func _plan_bots() -> void:
	_bots.clear()
	var n := maxi(0, rng.randi_range(bots_min, bots_max) - _last_real_answered)
	for i in n:
		var choice: int = current["answer"]
		if rng.randf() >= bot_accuracy:
			choice = (choice + rng.randi_range(1, 3)) % 4
		_bots.append({"id": "%s%d" % [BOT_PREFIX, i], "at": rng.randf_range(1.5, question_s - 2.0),
				"choice": choice})


func _run_bots(out: Array[Dictionary]) -> void:
	for bot in _bots.duplicate():
		if bot["at"] > _elapsed:
			continue
		_bots.erase(bot)
		var choice: int = bot["choice"]
		if choice in removed:                    # removed meanwhile: pick what is left
			var left := []
			for i in 4:
				if not (i in removed):
					left.append(i)
			choice = left[rng.randi_range(0, left.size() - 1)]
		_answer(bot["id"], choice, out)


# ---------------------------------------------------------------- helpers

func _ranked(points: Dictionary, n: int) -> Array:
	var ids := points.keys()
	ids.sort_custom(func(a, b): return points[a] > points[b])
	var out := []
	for uid in ids.slice(0, n):
		out.append({"user": players.get(uid, {"id": uid, "name": "?"}), "score": points[uid],
				"correct": correct.get(uid, 0)})
	return out


func _shuffled(list: Array) -> Array:
	var a := list.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a
