"""Fake viewers, for building and testing games without a live stream."""

from __future__ import annotations

import asyncio
import random

from ..normalizer import Normalizer
from . import SourceStatus

NAMES = [
    "Ahmad", "Lina", "Omar", "Sara", "Yousef", "Noor", "Khaled", "Maya", "Hamza", "Rania",
    "أحمد", "لينا", "عمر", "سارة", "يوسف", "نور", "خالد", "مايا", "حمزة", "رانيا",
    "gamer_99", "cat.lover", "shadow", "pixel", "falcon", "zaytoon", "qamar", "batman_ps", "tiger", "luna",
]
GIFTS = [(5655, "Rose", 1), (5269, "TikTok", 1), (5487, "Finger Heart", 5), (6064, "GG", 1),
         (5585, "Confetti", 100), (6267, "Corgi", 299), (5760, "Hand Hearts", 100), (6542, "Sunglasses", 199),
         (7934, "Heart Me", 1), (5827, "Ice Cream Cone", 1), (6104, "Cap", 99), (6369, "Lion", 29999)]
COMMENTS = ["!join", "join", "A", "B", "يلا", "واو 🔥", "مين بيفوز؟", "C", "D", "حلو", "go go"]

# (action, weight): roughly the mix seen on real streams, gifts are rare
ACTIONS = [("comment", 40), ("like", 40), ("follow", 6), ("share", 6), ("gift", 8)]


class MockSource:
    def __init__(self, rate: float = 3.0, seed: int | None = None):
        self.rate = max(rate, 0.1)
        self._rng = random.Random(seed)
        self.status = SourceStatus(name="mock")

    def _viewer(self, norm: Normalizer):
        i = self._rng.randrange(len(NAMES))
        user_id = str(1000 + i)
        avatar = f"https://api.dicebear.com/9.x/thumbs/png?size=64&seed={user_id}"
        return norm.viewer(user_id, NAMES[i], avatar)

    def step(self, norm: Normalizer) -> None:
        action = self._rng.choices([a for a, _ in ACTIONS], [w for _, w in ACTIONS])[0]
        user = self._viewer(norm)
        if action == "comment":
            norm.comment(user, self._rng.choice(COMMENTS))
        elif action == "like":
            norm.like(user, self._rng.randint(1, 15))
        elif action == "follow":
            norm.follow(user)
        elif action == "share":
            norm.share(user)
        else:
            gift_id, name, diamonds = self._rng.choice(GIFTS[:-1] if self._rng.random() < 0.98 else GIFTS)
            norm.gift(user, gift_id, name, diamonds, self._rng.randint(1, 5), streak_ended=True)

    async def run(self, norm: Normalizer) -> None:
        self.status.connected = True
        while True:
            self.step(norm)
            await asyncio.sleep(self._rng.expovariate(self.rate))
