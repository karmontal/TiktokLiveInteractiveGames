"""In-process fan-out of LiveEvents to every connected game client.

One bridge process serves one stream, so a plain asyncio fan-out is enough;
Redis can be added later if several processes ever need the same feed.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from collections import Counter, deque
from datetime import datetime, timezone
from pathlib import Path

from .events import LiveEvent

log = logging.getLogger(__name__)


class EventHub:
    def __init__(self, log_dir: Path | None = None, recent_size: int = 200, queue_size: int = 1000):
        self._subscribers: set[asyncio.Queue[dict]] = set()
        self._queue_size = queue_size
        self.recent: deque[dict] = deque(maxlen=recent_size)
        self._log_dir = log_dir
        if log_dir:
            log_dir.mkdir(parents=True, exist_ok=True)
        self.started_at = time.time()
        self.last_event_at: float | None = None
        self.counts: Counter[str] = Counter()
        self.viewers: set[str] = set()
        self.joined: set[str] = set()
        self.diamonds = 0

    def publish(self, event: LiveEvent) -> None:
        data = event.to_dict()
        self._track(event)
        self.recent.append(data)
        self._write_log(data)
        for queue in self._subscribers:
            if queue.full():  # a slow client loses its oldest events, never blocks the stream
                queue.get_nowait()
            queue.put_nowait(data)

    def subscribe(self) -> asyncio.Queue[dict]:
        queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=self._queue_size)
        self._subscribers.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue[dict]) -> None:
        self._subscribers.discard(queue)

    @property
    def client_count(self) -> int:
        return len(self._subscribers)

    def stats(self) -> dict:
        return {
            "uptime_s": round(time.time() - self.started_at),
            "last_event_age_s": round(time.time() - self.last_event_at, 1) if self.last_event_at else None,
            "clients": self.client_count,
            "events": dict(self.counts),
            "unique_viewers": len(self.viewers),
            "joined_viewers": len(self.joined),
            "diamonds": self.diamonds,
        }

    def _track(self, event: LiveEvent) -> None:
        self.last_event_at = event.ts
        self.counts[event.type] += 1
        if event.user:
            self.viewers.add(event.user.id)
        if event.type == "join" and event.user:
            self.joined.add(event.user.id)
        if event.type == "gift":
            self.diamonds += event.value

    def _write_log(self, data: dict) -> None:
        if not self._log_dir:
            return
        day = datetime.fromtimestamp(data["ts"], tz=timezone.utc).strftime("%Y-%m-%d")
        try:
            with open(self._log_dir / f"events-{day}.jsonl", "a", encoding="utf-8") as fh:
                fh.write(json.dumps(data, ensure_ascii=False) + "\n")
        except OSError:
            log.exception("could not write event log")
