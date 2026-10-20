extends SceneTree
## Headless unit tests: godot --headless --path arena -s res://tests/run_tests.gd

const ArenaLogic := preload("res://logic/ArenaLogic.gd")
const ArenaCamera := preload("res://logic/ArenaCamera.gd")

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


func arena() -> ArenaLogic:
	var a := ArenaLogic.new()
	a.rng.seed = 11
	a.start()
	return a


func kinds(out: Array[Dictionary]) -> Array:
	return out.map(func(fx): return fx["kind"])


## Puts two fighters face to face, done dropping in.
func duel(a: ArenaLogic, gap := 1.0) -> void:
	a.handle({"type": "join", "user": u("1")})
	a.handle({"type": "join", "user": u("2")})
	for id in ["1", "2"]:
		a.fighters[id]["drop"] = 0.0
		a.fighters[id]["cooldown"] = 0.0
	a.fighters["1"]["pos"] = Vector2(-gap / 2, 0)
	a.fighters["2"]["pos"] = Vector2(gap / 2, 0)


func test_any_interaction_drops_a_fighter_in() -> void:
	var a := arena()
	check(kinds(a.handle({"type": "comment", "user": u("1"), "text": "يلا"})) == ["joined"], "comment joins")
	var out := a.handle({"type": "like", "user": u("2"), "count": 5})
	check(kinds(out) == ["joined", "power"], "a like joins and powers up")
	check(a.fighters["1"]["drop"] > 0.0 and a.fighters["1"]["pos"].length() < a.radius(), "drops onto the island")
	check(kinds(a.handle({"type": "comment", "user": u("1"), "text": "x"})).is_empty(), "joins once")


func test_fighters_walk_to_each_other_and_punch() -> void:
	var a := arena()
	duel(a, 6.0)
	var punches := 0
	for i in 90:
		punches += kinds(a.tick(0.1)).count("punch")
	check(punches > 0, "they meet and punch (%d)" % punches)
	check(a.fighters["1"]["damage"] > 0.0 or a.fighters["2"]["damage"] > 0.0, "damage taken")


func test_knockback_grows_with_damage() -> void:
	var a := arena()
	duel(a)
	var out: Array[Dictionary] = []
	a._punch(a.fighters["1"], a.fighters["2"], 1.0, out)
	var first: float = out[0]["push"]
	a.fighters["2"]["damage"] = 120.0
	a._punch(a.fighters["1"], a.fighters["2"], 1.0, out)
	check(out[1]["push"] > first * 2.0, "a beaten fighter flies further")


func test_likes_add_power_and_it_fades() -> void:
	var a := arena()
	duel(a)
	a.handle({"type": "like", "user": u("1"), "count": 100})
	check(is_equal_approx(a.fighters["1"]["power"], a.max_power), "capped")
	var out: Array[Dictionary] = []
	a._punch(a.fighters["1"], a.fighters["2"], 1.0, out)
	check(is_equal_approx(out[0]["push"], (a.knock_base + a.punch_damage * a.knock_per_damage) * 2.0), "double knockback")
	a.fighters["1"]["pos"] = Vector2(-5, 0)
	a.tick(3.0)
	check(a.fighters["1"]["power"] < a.max_power, "power fades")


func test_follow_shield_blocks_one_punch() -> void:
	var a := arena()
	duel(a)
	a.handle({"type": "follow", "user": u("2")})
	var out: Array[Dictionary] = []
	a._punch(a.fighters["1"], a.fighters["2"], 1.0, out)
	check(kinds(out) == ["shield_break"] and a.fighters["2"]["damage"] == 0.0, "blocked")
	a._punch(a.fighters["1"], a.fighters["2"], 1.0, out)
	check(kinds(out)[-1] == "punch", "second one lands")


func test_small_gift_heals_medium_hammer_large_giant() -> void:
	var a := arena()
	duel(a, 1.0)
	a.handle({"type": "join", "user": u("3")})
	a.fighters["3"]["drop"] = 0.0
	a.fighters["3"]["pos"] = Vector2(0, 1.5)
	a.fighters["2"]["damage"] = 50.0
	check(kinds(a.handle({"type": "gift", "user": u("2"), "count": 1, "gift": {"tier": "small"}})) == ["heal"], "heal")
	check(a.fighters["2"]["damage"] == 0.0, "damage gone")
	a.handle({"type": "gift", "user": u("2"), "count": 1, "gift": {"tier": "medium"}})
	check(a.fighters["2"]["hammer"] > 0.0, "hammer on")
	var out := a.handle({"type": "gift", "user": u("1"), "count": 1, "gift": {"tier": "large"}})
	check(kinds(out) == ["giant", "shockwave"] and out[1]["hit"] == 2, "giant + shockwave hits both")
	check(a.fighters["2"]["vel"].length() > 3.0 and a.fighters["2"]["last_hitter"] == "1", "pushed away")
	check(a.size_of(a.fighters["1"]) == a.giant_size and a.fighters["2"]["gifts"] == 2, "big, gifts counted")
	a.tick(a.giant_s + 0.1)
	check(a.size_of(a.fighters["1"]) == 1.0, "giant wears off")


func test_share_dashes_into_rival() -> void:
	var a := arena()
	duel(a, 4.0)
	a.fighters["1"]["cooldown"] = 9.0
	a.fighters["2"]["cooldown"] = 9.0
	check(kinds(a.handle({"type": "share", "user": u("1")})) == ["dash"], "dash")
	var hit := false
	for i in 6:
		hit = hit or "punch" in kinds(a.tick(0.1))
	check(hit, "rams the rival")


func test_off_the_edge_is_a_ko_for_the_last_hitter() -> void:
	var a := arena()
	duel(a)
	a.fighters["2"]["pos"] = Vector2(a.radius() - 0.3, 0)
	a.fighters["1"]["pos"] = Vector2(a.radius() - 1.3, 0)
	a.fighters["2"]["damage"] = 200.0
	a.fighters["2"]["cooldown"] = 9.0
	var out: Array[Dictionary] = []
	for i in 10:
		out.append_array(a.tick(0.1))
	check("ko" in kinds(out), "knocked off")
	check(a.fighters["1"]["kos"] == 1 and not a.fighters["2"]["alive"], "KO credited")
	check("round_end" in kinds(out) and a.winner["user"]["id"] == "1" and a.winner["last_standing"], "last one standing wins")


func test_walking_off_alone_gives_no_credit() -> void:
	var a := arena()
	duel(a, 8.0)
	a.fighters["2"]["pos"] = Vector2(0, a.radius() + 0.5)
	var out := a.tick(0.05)
	check("ko" in kinds(out) and out[kinds(out).find("ko")]["by"].is_empty(), "nobody gets it")


func test_edge_collapses_every_minute_with_warning() -> void:
	var a := arena()
	duel(a, 2.0)
	for id in ["1", "2"]:
		a.fighters[id]["cooldown"] = 999.0
	a.cooldown_min = 999.0
	a.cooldown_max = 999.0
	a.fighters["2"]["pos"] = Vector2(8.0, 0)       # stands on the outer ring
	a.fighters["1"]["pos"] = Vector2(0, 0)
	a.walk_speed = 0.0
	var out: Array[Dictionary] = []
	for i in 600:
		out.append_array(a.tick(0.1))
		if "collapse" in kinds(out):
			break
	var k := kinds(out)
	check(k.find("warning") >= 0 and k.find("warning") < k.find("collapse"), "warned first")
	check(a.stage == 1 and is_equal_approx(a.radius(), 7.5), "smaller island")
	check(not a.fighters["2"]["alive"], "the ring took them")


func test_timeout_most_kos_wins_and_hall_of_fame() -> void:
	var a := arena()
	duel(a, 2.0)
	a.fighters["2"]["kos"] = 3
	a.time_left = 0.05
	a.walk_speed = 0.0
	a.cooldown_min = 99.0
	a.cooldown_max = 99.0
	a.fighters["1"]["cooldown"] = 99.0
	a.fighters["2"]["cooldown"] = 99.0
	var out := a.tick(0.1)
	check(kinds(out)[-1] == "round_end" and a.winner["user"]["id"] == "2", "most KOs among the standing")
	check(a.wins["2"] == 1 and a.total_kos["2"] == 3, "stream totals")
	check(a.hall_of_fame()[0]["user"]["id"] == "2", "hall of fame")
	check(a.handle({"type": "like", "user": u("9"), "count": 3}).is_empty(), "no joining between rounds")
	out = a.tick(a.result_s + 0.1)
	check(kinds(out) == ["round_start"] and out[0]["fighters"] == 3, "next round brings everyone back")


func test_one_viewer_alone_keeps_fighting() -> void:
	var a := arena()
	a.handle({"type": "join", "user": u("1")})
	check(a.tick(1.0).filter(func(fx): return fx["kind"] == "round_end").is_empty(), "no instant win alone")


func test_max_fighters() -> void:
	var a := arena()
	a.max_fighters = 3
	for i in 5:
		a.handle({"type": "join", "user": u(str(i))})
	check(a.fighters.size() == 3, "capped")


func test_stream_end_resets() -> void:
	var a := arena()
	duel(a)
	a.wins["1"] = 2
	a.handle({"type": "stream_end"})
	check(a.wins.is_empty() and a.fighters.is_empty() and a.round_no == 1, "fresh stream")


# ---------------------------------------------------------------- camera

func cam() -> ArenaCamera:
	var c := ArenaCamera.new()
	c.rng.seed = 5
	return c


func test_camera_wide_when_alone() -> void:
	var a := arena()
	check(cam().tick(0.1, a)["kind"] == "wide", "nothing to frame")


func test_camera_follows_fights_mostly_the_leader() -> void:
	var a := arena()
	for i in 6:
		a.handle({"type": "join", "user": u(str(i))})
	a.fighters["3"]["kos"] = 4
	var c := cam()
	var leader := 0
	var fights := 0
	for i in 400:
		var before = c.shot.duplicate()
		var s := c.tick(0.5, a)
		if before.is_empty() or s["left"] > before["left"]:
			if s["kind"] == "fight":
				fights += 1
				leader += 1 if s["uid"] == "3" else 0
	check(fights > 0 and float(leader) / fights > 0.45, "leader gets about half the fights (%d/%d)" % [leader, fights])


func test_camera_priorities() -> void:
	var a := arena()
	duel(a)
	var c := cam()
	c.tick(0.1, a)
	c.joined(u("1"))
	check(c.tick(0.1, a)["kind"] == "join", "newcomer")
	c.collapse(4.0)
	c.ko(u("2"), Vector2.ZERO)
	c.giant(u("2"), Vector2.ZERO)
	c.joined(u("2"))
	check(c.tick(1.0, a)["kind"] == "collapse", "collapse beats everything")
	c.tick(3.5, a)
	c.ko(u("2"), Vector2(1, 1))
	check(c.tick(0.1, a)["kind"] == "ko", "then the knockout")
