extends SceneTree
## Headless unit tests: godot --headless --path game -s res://tests/run_tests.gd

const TugLogic := preload("res://games/tug_of_war/TugLogic.gd")
const QuizLogic := preload("res://games/quiz/QuizLogic.gd")
const QUIZ_PACK := "res://games/quiz/packs/general.json"

var _failed := 0
var _passed := 0


func _init() -> void:
	for method in get_method_list():
		var name: String = method["name"]
		if name.begins_with("test_"):
			call(name)
	print("%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: ", what)


func u(id: String) -> Dictionary:
	return {"id": id, "name": "P" + id, "avatar": ""}


func test_comment_letter_picks_team() -> void:
	var t := TugLogic.new()
	t.handle({"type": "comment", "user": u("1"), "text": " a "})
	t.handle({"type": "comment", "user": u("2"), "text": "ب"})
	check(t.team_of["1"] == TugLogic.A, "a joins A")
	check(t.team_of["2"] == TugLogic.B, "ب joins B")


func test_other_comments_do_not_join() -> void:
	var t := TugLogic.new()
	t.handle({"type": "comment", "user": u("1"), "text": "hello"})
	check(t.team_of.is_empty(), "plain comment joins nobody")


func test_auto_team_balances() -> void:
	var t := TugLogic.new()
	for i in 4:
		t.handle({"type": "join", "user": u(str(i))})
	check(t.team_count(TugLogic.A) == 2 and t.team_count(TugLogic.B) == 2, "joins alternate teams")


func test_like_from_stranger_joins_and_pulls() -> void:
	var t := TugLogic.new()
	var out := t.handle({"type": "like", "user": u("1"), "count": 10})
	check(out[0]["kind"] == "joined" and out[1]["kind"] == "pull", "joined then pulled")
	check(is_equal_approx(t.rope, -10 * t.like_pull), "team A pulls toward -1")


func test_team_b_pulls_positive() -> void:
	var t := TugLogic.new()
	t.handle({"type": "comment", "user": u("1"), "text": "B"})
	t.handle({"type": "follow", "user": u("1")})
	check(is_equal_approx(t.rope, t.follow_pull), "B pulls toward +1")


func test_gift_is_capped() -> void:
	var t := TugLogic.new()
	t.handle({"type": "gift", "user": u("1"), "value": 29999, "count": 1, "gift": {"tier": "large"}})
	check(is_equal_approx(absf(t.rope), t.gift_pull_cap), "big gift capped")
	check(t.winner() == TugLogic.NONE, "one gift does not win")


func test_share_doubles_team_pull_for_a_while() -> void:
	var t := TugLogic.new()
	t.handle({"type": "share", "user": u("1")})
	t.handle({"type": "like", "user": u("1"), "count": 10})
	check(is_equal_approx(t.rope, -10 * t.like_pull * t.share_multiplier), "boosted pull")
	t.tick(t.share_boost_s + 0.1)
	var before := t.rope
	t.handle({"type": "like", "user": u("1"), "count": 10})
	check(is_equal_approx(t.rope - before, -10 * t.like_pull), "boost expired")


func test_rope_clamps_and_wins() -> void:
	var t := TugLogic.new()
	t.handle({"type": "comment", "user": u("1"), "text": "A"})
	for i in 10:
		t.handle({"type": "gift", "user": u("1"), "value": 100, "count": 1, "gift": {}})
	check(t.rope == -1.0, "rope clamps at -1")
	check(t.winner() == TugLogic.A, "A wins")


func test_inactive_round_does_not_move_rope() -> void:
	var t := TugLogic.new()
	t.active = false
	t.handle({"type": "like", "user": u("1"), "count": 50})
	check(t.rope == 0.0, "no pull between rounds")
	check(t.team_of.has("1"), "but the viewer still gets a team")


func test_mvp_and_new_round() -> void:
	var t := TugLogic.new()
	t.handle({"type": "comment", "user": u("1"), "text": "A"})
	t.handle({"type": "comment", "user": u("2"), "text": "A"})
	t.handle({"type": "like", "user": u("1"), "count": 5})
	t.handle({"type": "like", "user": u("2"), "count": 20})
	check(t.mvp(TugLogic.A)["user"]["id"] == "2", "biggest puller is MVP")
	check(t.mvp(TugLogic.B).is_empty(), "empty team has no MVP")
	t.new_round()
	check(t.rope == 0.0 and t.contribution.is_empty(), "round reset")
	check(t.team_of.size() == 2, "teams kept across rounds")


func bots_in(t, team: int) -> int:
	var n := 0
	for uid in t.team_of:
		if TugLogic.is_bot(uid) and t.team_of[uid] == team:
			n += 1
	return n


func test_bots_spawn_balanced() -> void:
	var t := TugLogic.new()
	t.spawn_bots(7)
	check(t.team_of.size() == 7, "7 bots spawned")
	check(absi(bots_in(t, TugLogic.A) - bots_in(t, TugLogic.B)) <= 1, "bots split evenly")


func test_respawn_replaces_old_bots() -> void:
	var t := TugLogic.new()
	t.spawn_bots(10)
	var out := t.spawn_bots(5)
	check(t.team_of.size() == 5, "only the new bots remain")
	check(out.filter(func(fx): return fx["kind"] == "left").size() == 10, "old bots left")


func test_bots_pull_weakly_and_cancel_out() -> void:
	var t := TugLogic.new()
	t.rng.seed = 42
	t.spawn_bots(8)
	var pulls := 0
	for i in 600:                       # 60 seconds
		for fx in t.tick(0.1):
			pulls += 1
			check(is_equal_approx(fx["amount"], t.bot_pull), "bot pull is tiny")
	check(pulls > 50, "bots keep pulling (%d)" % pulls)
	check(absf(t.rope) < 0.1, "8 bots alone stay near the center (%.3f)" % t.rope)


func test_real_viewer_replaces_a_bot() -> void:
	var t := TugLogic.new()
	t.spawn_bots(6)
	var before := bots_in(t, TugLogic.A)
	var out := t.handle({"type": "comment", "user": u("1"), "text": "A"})
	check(bots_in(t, TugLogic.A) == before - 1, "one bot left team A")
	check(out[1]["kind"] == "left", "left effect for the screen")


func test_bot_is_never_mvp() -> void:
	var t := TugLogic.new()
	t.spawn_bots(2)
	for i in 100:
		t.tick(1.0)
	check(t.mvp(TugLogic.A).is_empty() and t.mvp(TugLogic.B).is_empty(), "bots are not MVP")
	t.handle({"type": "comment", "user": u("1"), "text": "A"})
	t.handle({"type": "like", "user": u("1"), "count": 1})
	check(t.mvp(TugLogic.A)["user"]["id"] == "1", "a real viewer is MVP")


func test_switching_team() -> void:
	var t := TugLogic.new()
	t.handle({"type": "comment", "user": u("1"), "text": "A"})
	var out := t.handle({"type": "comment", "user": u("1"), "text": "B"})
	check(t.team_of["1"] == TugLogic.B and out[0]["switched"], "can switch team")
	check(t.handle({"type": "comment", "user": u("1"), "text": "B"}).is_empty(), "same team is a no-op")


# ---------------------------------------------------------------- quiz

func quiz(bots := false) -> QuizLogic:
	var q := QuizLogic.new()
	q.rng.seed = 7
	if not bots:
		q.bots_min = 0
		q.bots_max = 0
	q.load_questions(JSON.parse_string(FileAccess.get_file_as_string(QUIZ_PACK))["questions"])
	q.start()
	return q


func to_question(q: QuizLogic) -> void:
	q.tick(q.time_left + 0.01)


func say(q: QuizLogic, uid: String, text: String) -> Array:
	return q.handle({"type": "comment", "user": u(uid), "text": text})


func letter_of(q: QuizLogic, right: bool) -> String:
	var i: int = q.current["answer"] if right else (q.current["answer"] + 1) % 4
	return QuizLogic.LETTERS[i]


func test_quiz_pack_is_valid() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(QUIZ_PACK))
	var texts := {}
	for item in data["questions"]:
		check(item["options"].size() == 4, "4 options: " + item["q"])
		var unique := {}
		for o in item["options"]:
			unique[o] = true
		check(unique.size() == 4, "options differ: " + item["q"])
		check(not texts.has(item["q"]), "no duplicate question: " + item["q"])
		texts[item["q"]] = true
	var q := quiz()
	check(q.categories().size() >= 4, "enough categories")
	for c in q.categories():
		check(q._by_category[c].size() >= 10, "a full round fits in " + c)


func test_quiz_parse_choice() -> void:
	check(QuizLogic.parse_choice(" a ") == 0, "a")
	check(QuizLogic.parse_choice("ب") == 1, "ب")
	check(QuizLogic.parse_choice("٣") == 2, "Arabic 3")
	check(QuizLogic.parse_choice("D") == 3, "D")
	check(QuizLogic.parse_choice("hello") == -1, "not an answer")
	check(QuizLogic.parse_choice("AB") == -1, "two letters is not an answer")


func test_quiz_round_setup() -> void:
	var seen_sizes := {}
	for i in 40:
		var q := QuizLogic.new()
		q.rng.seed = i
		q.load_questions(JSON.parse_string(FileAccess.get_file_as_string(QUIZ_PACK))["questions"])
		q.start()
		var n := q.round_categories.size()
		seen_sizes[n] = true
		check(n >= 1 and n <= 4, "1 to 4 categories (%d)" % n)
		check(q.round_questions.size() == 10, "10 questions per round")
		for item in q.round_questions:
			check(item["category"] in q.round_categories, "question from a picked category")
	check(seen_sizes.has(1) and seen_sizes.has(4), "both 1 and 4 categories happen")


func test_quiz_options_are_shuffled_but_answer_tracks() -> void:
	var q := quiz()
	var positions := {}
	for i in 10:
		to_question(q)
		var item: Dictionary = q.round_questions[q.question_index]
		check(q.current["options"][q.current["answer"]] == item["options"][0], "answer index follows the shuffle")
		positions[q.current["answer"]] = true
		q.tick(q.time_left + 0.01)   # reveal
	check(positions.size() >= 3, "the right answer moves between letters")


func test_quiz_first_answer_counts() -> void:
	var q := quiz()
	to_question(q)
	say(q, "1", "A")
	say(q, "1", "B")
	check(q.answers["1"]["choice"] == 0 and q.counts == [1, 0, 0, 0], "second answer ignored")


func test_quiz_follow_lets_you_change_once() -> void:
	var q := quiz()
	to_question(q)
	q.handle({"type": "follow", "user": u("1")})
	say(q, "1", "A")
	say(q, "1", "B")
	say(q, "1", "C")
	check(q.answers["1"]["choice"] == 1, "changed once to B, not again to C")
	check(q.counts == [0, 1, 0, 0], "counts follow the change")


func test_quiz_scoring_by_speed() -> void:
	var q := quiz()
	to_question(q)
	say(q, "fast", letter_of(q, true))
	q.tick(7.5)
	say(q, "slow", letter_of(q, true))
	say(q, "wrong", letter_of(q, false))
	var out := q.tick(q.time_left + 0.01)
	check(q.score["fast"] == 200, "instant answer = 200 (%s)" % q.score.get("fast"))
	check(q.score["slow"] == 150, "half time = 150 (%s)" % q.score.get("slow"))
	check(not q.score.has("wrong"), "wrong answer scores nothing")
	var reveal: Dictionary = out[0]
	check(reveal["kind"] == "reveal" and reveal["fastest"][0]["user"]["id"] == "fast", "fastest first")


func test_quiz_share_and_gifts_multiply_next_right_answer() -> void:
	var q := quiz()
	to_question(q)
	q.handle({"type": "share", "user": u("s")})
	q.handle({"type": "gift", "user": u("g"), "count": 1, "value": 299, "gift": {"tier": "large"}})
	say(q, "s", letter_of(q, true))
	say(q, "g", letter_of(q, true))
	q.tick(q.time_left + 0.01)
	check(q.score["s"] == 400, "share = x2 (%s)" % q.score.get("s"))
	check(q.score["g"] == 600, "big gift = x3 (%s)" % q.score.get("g"))
	check(not q.multiplier.has("s"), "multiplier used up")


func test_quiz_wrong_answer_keeps_multiplier() -> void:
	var q := quiz()
	to_question(q)
	q.handle({"type": "share", "user": u("s")})
	say(q, "s", letter_of(q, false))
	q.tick(q.time_left + 0.01)
	check(q.multiplier.get("s", 1) == 2, "x2 waits for the next right answer")


func test_quiz_gift_time_is_capped() -> void:
	var q := quiz()
	to_question(q)
	var before := q.time_left
	for i in 10:
		q.handle({"type": "gift", "user": u("g"), "count": 1, "value": 1, "gift": {"tier": "small"}})
	check(is_equal_approx(q.time_left - before, q.max_extra_seconds), "extra time capped at 20 s")


func test_quiz_likes_remove_wrong_answers() -> void:
	var q := quiz()
	to_question(q)
	var out := q.handle({"type": "like", "user": u("1"), "count": 49})
	check(q.removed.is_empty(), "49 likes: nothing yet")
	q.handle({"type": "like", "user": u("1"), "count": 1})
	check(q.removed.size() == 1, "50 likes remove one")
	q.handle({"type": "like", "user": u("1"), "count": 500})
	check(q.removed.size() == 2, "never more than 2 removed")
	check(not (q.current["answer"] in q.removed), "the right answer is never removed")
	var removed_letter: String = QuizLogic.LETTERS[q.removed[0]]
	say(q, "2", removed_letter)
	check(not q.answers.has("2"), "removed option cannot be picked")


func test_quiz_bots_answer_but_never_score() -> void:
	var q := quiz(true)
	to_question(q)
	for i in 150:
		q.tick(0.1)
	check(q.answered_count() >= 5, "bots answered (%d)" % q.answered_count())
	q.tick(q.time_left + 0.01)
	check(q.score.is_empty() and q.top(10).is_empty(), "bots never on the leaderboard")


func test_quiz_real_viewers_replace_bots() -> void:
	var q := quiz(true)
	q.bots_min = 6
	q.bots_max = 6
	to_question(q)
	for i in 4:
		say(q, str(i), "A")
	q.tick(q.time_left + 0.01)      # reveal: 4 real answered
	q.tick(q.time_left + 0.01)      # next question
	for i in 150:
		q.tick(0.1)
	check(q.answered_count() == 2, "6 bots - 4 real viewers = 2 bots (%d)" % q.answered_count())


func test_quiz_round_cycle_board_and_champion() -> void:
	var q := quiz()
	var kinds := []
	for i in 10:
		to_question(q)                     # intermission or reveal -> question
		say(q, "star", letter_of(q, true))
		for fx in q.tick(q.time_left + 0.01):
			kinds.append(fx["kind"])       # question -> reveal
	for fx in q.tick(q.time_left + 0.01):
		kinds.append(fx["kind"])           # last reveal -> board
	check(kinds.count("reveal") == 10 and kinds[-1] == "board", "10 questions then the board")
	check(q.top(1)[0]["user"]["id"] == "star" and q.top(1)[0]["correct"] == 10, "board ranks the stream")
	var out := q.tick(q.time_left + 0.01)
	check(out[0]["kind"] == "intermission" and out[0]["champion"]["user"]["id"] == "star", "round champion shown")
	check(q.round_score.is_empty() and q.score.has("star"), "round score resets, stream score stays")


func test_quiz_stream_end_resets_leaderboard() -> void:
	var q := quiz()
	to_question(q)
	say(q, "1", letter_of(q, true))
	q.tick(q.time_left + 0.01)
	check(q.score.has("1"), "scored")
	q.handle({"type": "stream_end"})
	check(q.score.is_empty() and q.top(10).is_empty(), "new stream, empty leaderboard")


func test_quiz_no_repeats_within_a_stream() -> void:
	var q := quiz()
	var asked := {}
	var repeats := 0
	for r in 6:                      # 60 questions out of 77
		for i in 10:
			to_question(q)
			if asked.has(q.current["text"]):
				repeats += 1
			asked[q.current["text"]] = true
			q.tick(q.time_left + 0.01)
		q.tick(q.time_left + 0.01)   # board -> intermission
	check(repeats < 10, "few repeats while fresh questions remain (%d)" % repeats)
