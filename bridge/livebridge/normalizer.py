"""Turns raw viewer actions into LiveEvents.

Sources (TikTok, mock) call these methods with plain values, so all the
rules live here and are testable without a real stream. Game-specific
effects (how far a like pulls the rope, etc.) belong in the game, not here.
"""

from __future__ import annotations

from typing import Callable

from .events import GiftInfo, GiftTier, LiveEvent, Viewer
from .moderation import Moderator

DEFAULT_JOIN_KEYWORDS = ("!join", "join", "دخول", "ادخل")


def gift_tier(diamonds: int) -> GiftTier:
    if diamonds >= 100:
        return "large"
    if diamonds >= 10:
        return "medium"
    return "small"


class Normalizer:
    def __init__(
        self,
        emit: Callable[[LiveEvent], None],
        moderator: Moderator | None = None,
        join_keywords: tuple[str, ...] = DEFAULT_JOIN_KEYWORDS,
    ):
        self._emit = emit
        self._mod = moderator or Moderator([])
        self._join_keywords = {k.casefold() for k in join_keywords}
        self._followed: set[str] = set()
        # (user_id, gift_id) -> units already emitted in the running streak
        self._streaks: dict[tuple[str, int], int] = {}

    def reset_session(self) -> None:
        self._followed.clear()
        self._streaks.clear()

    def viewer(self, user_id: str, name: str, avatar: str = "") -> Viewer:
        return Viewer(id=str(user_id), name=self._mod.clean_name(name, str(user_id)), avatar=avatar)

    def comment(self, user: Viewer, text: str) -> None:
        if text.strip().casefold() in self._join_keywords:
            self._emit(LiveEvent("join", user))
        shown = self._mod.clean_text(text)
        if shown:
            self._emit(LiveEvent("comment", user, text=shown))

    def like(self, user: Viewer, count: int) -> None:
        if count > 0:
            self._emit(LiveEvent("like", user, count=count, value=count))

    def follow(self, user: Viewer) -> None:
        # Unfollow/refollow spam must not farm boosts: one follow per user per session.
        if user.id in self._followed:
            return
        self._followed.add(user.id)
        self._emit(LiveEvent("follow", user))

    def share(self, user: Viewer) -> None:
        self._emit(LiveEvent("share", user))

    def gift(
        self,
        user: Viewer,
        gift_id: int,
        gift_name: str,
        diamonds: int,
        repeat_count: int,
        streak_ended: bool,
    ) -> None:
        """Emit only the units not yet emitted, so streak gifts show up live
        (x1, x2, x3 ...) without being counted twice when the streak ends."""
        key = (user.id, gift_id)
        already = self._streaks.get(key, 0)
        if repeat_count < already:  # a new streak started before the old one closed
            already = 0
        new_units = repeat_count - already
        if streak_ended:
            self._streaks.pop(key, None)
        else:
            self._streaks[key] = repeat_count
        if new_units <= 0:
            return
        info = GiftInfo(id=gift_id, name=gift_name, diamonds=diamonds, tier=gift_tier(diamonds))
        self._emit(LiveEvent("gift", user, count=new_units, gift=info, value=new_units * diamonds))

    def stream_end(self) -> None:
        self._emit(LiveEvent("stream_end"))
        self.reset_session()
