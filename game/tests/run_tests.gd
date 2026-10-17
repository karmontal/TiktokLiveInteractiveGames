extends SceneTree
## Headless unit tests: godot --headless --path game -s res://tests/run_tests.gd

const TugLogic := preload("res://games/tug_of_war/TugLogic.gd")

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


func test_switching_team() -> void:
	var t := TugLogic.new()
	t.handle({"type": "comment", "user": u("1"), "text": "A"})
	var out := t.handle({"type": "comment", "user": u("1"), "text": "B"})
	check(t.team_of["1"] == TugLogic.B and out[0]["switched"], "can switch team")
	check(t.handle({"type": "comment", "user": u("1"), "text": "B"}).is_empty(), "same team is a no-op")
