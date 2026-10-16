from livebridge.moderation import Moderator
from livebridge.normalizer import Normalizer, gift_tier


def make(banned=()):
    events = []
    norm = Normalizer(events.append, Moderator(list(banned)))
    return norm, events


def test_join_keyword_emits_join_and_comment():
    norm, events = make()
    norm.comment(norm.viewer("1", "Omar"), "  !JOIN ")
    assert [e.type for e in events] == ["join", "comment"]


def test_arabic_join_keyword():
    norm, events = make()
    norm.comment(norm.viewer("1", "عمر"), "دخول")
    assert events[0].type == "join"


def test_plain_comment_does_not_join():
    norm, events = make()
    norm.comment(norm.viewer("1", "Omar"), "A")
    assert [(e.type, e.text) for e in events] == [("comment", "A")]


def test_banned_comment_is_hidden_but_join_still_counts():
    norm, events = make(banned=["join"])
    norm.comment(norm.viewer("1", "Omar"), "join")
    assert [e.type for e in events] == ["join"]


def test_follow_only_once_per_session():
    norm, events = make()
    user = norm.viewer("1", "Omar")
    norm.follow(user)
    norm.follow(user)
    assert len(events) == 1
    norm.reset_session()
    norm.follow(user)
    assert len(events) == 2


def test_zero_likes_are_dropped():
    norm, events = make()
    norm.like(norm.viewer("1", "Omar"), 0)
    norm.like(norm.viewer("1", "Omar"), 7)
    assert [(e.count, e.value) for e in events] == [(7, 7)]


def test_gift_streak_emits_only_new_units():
    norm, events = make()
    user = norm.viewer("1", "Omar")
    norm.gift(user, 5655, "Rose", 1, repeat_count=1, streak_ended=False)
    norm.gift(user, 5655, "Rose", 1, repeat_count=3, streak_ended=False)
    norm.gift(user, 5655, "Rose", 1, repeat_count=3, streak_ended=True)  # final event repeats the total
    assert [e.count for e in events] == [1, 2]
    assert sum(e.value for e in events) == 3


def test_new_streak_after_end_counts_from_zero():
    norm, events = make()
    user = norm.viewer("1", "Omar")
    norm.gift(user, 5655, "Rose", 1, repeat_count=2, streak_ended=True)
    norm.gift(user, 5655, "Rose", 1, repeat_count=1, streak_ended=False)
    assert [e.count for e in events] == [2, 1]


def test_restarted_streak_without_end_is_not_lost():
    norm, events = make()
    user = norm.viewer("1", "Omar")
    norm.gift(user, 5655, "Rose", 1, repeat_count=5, streak_ended=False)
    norm.gift(user, 5655, "Rose", 1, repeat_count=2, streak_ended=False)
    assert [e.count for e in events] == [5, 2]


def test_gift_value_and_tier():
    norm, events = make()
    norm.gift(norm.viewer("1", "Omar"), 6267, "Corgi", 299, repeat_count=2, streak_ended=True)
    (event,) = events
    assert event.value == 598
    assert event.gift.tier == "large"


def test_gift_tiers_match_plan():
    assert gift_tier(1) == "small"
    assert gift_tier(9) == "small"
    assert gift_tier(10) == "medium"
    assert gift_tier(99) == "medium"
    assert gift_tier(100) == "large"


def test_stream_end_resets_follow_dedupe():
    norm, events = make()
    user = norm.viewer("1", "Omar")
    norm.follow(user)
    norm.stream_end()
    norm.follow(user)
    assert [e.type for e in events] == ["follow", "stream_end", "follow"]


def test_event_dict_shape():
    norm, events = make()
    norm.like(norm.viewer("1", "Omar", "http://a/x.png"), 3)
    data = events[0].to_dict()
    assert data["user"] == {"id": "1", "name": "Omar", "avatar": "http://a/x.png"}
    assert "text" not in data and "gift" not in data
