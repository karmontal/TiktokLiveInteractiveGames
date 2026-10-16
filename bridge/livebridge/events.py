"""Normalized event format shared by every source and every game client.

Wire format (one JSON object per WebSocket message):

    {
      "type":  "join" | "comment" | "like" | "follow" | "share" | "gift" | "stream_end",
      "user":  {"id": "...", "name": "...", "avatar": "https://..."} | null,
      "text":  "comment text",            # comment only
      "count": 3,                         # like: likes in this batch, gift: units in this batch
      "gift":  {"id": 5655, "name": "Rose", "diamonds": 1, "tier": "small"},  # gift only
      "value": 3,                         # gift: diamonds in this batch, like: same as count
      "ts":    1760000000.123
    }
"""

from __future__ import annotations

import time
from dataclasses import asdict, dataclass, field
from typing import Literal, Optional

EventType = Literal["join", "comment", "like", "follow", "share", "gift", "stream_end"]
GiftTier = Literal["small", "medium", "large"]


@dataclass(frozen=True)
class Viewer:
    id: str
    name: str
    avatar: str = ""


@dataclass(frozen=True)
class GiftInfo:
    id: int
    name: str
    diamonds: int
    tier: GiftTier


@dataclass(frozen=True)
class LiveEvent:
    type: EventType
    user: Optional[Viewer] = None
    text: str = ""
    count: int = 0
    gift: Optional[GiftInfo] = None
    value: int = 0
    ts: float = field(default_factory=time.time)

    def to_dict(self) -> dict:
        data = asdict(self)
        if self.type != "comment":
            data.pop("text")
        if self.gift is None:
            data.pop("gift")
        return data
