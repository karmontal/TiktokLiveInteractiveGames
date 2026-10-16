"""Event API: games connect to /ws and receive one JSON event per message."""

from __future__ import annotations

import asyncio
import logging
import secrets
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

from .config import Settings
from .hub import EventHub
from .moderation import Moderator
from .normalizer import Normalizer

log = logging.getLogger(__name__)

KEEPALIVE_S = 15


def make_source(settings: Settings):
    if settings.source == "tiktok":
        from .sources.tiktok import TikTokSource
        return TikTokSource(settings.tiktok_username, settings.sign_api_key)
    if settings.source == "mock":
        from .sources.mock import MockSource
        return MockSource(rate=settings.mock_rate)
    raise ValueError(f"unknown LIVEBRIDGE_SOURCE: {settings.source!r} (use 'mock' or 'tiktok')")


class DebugEvent(BaseModel):
    type: Literal["join", "comment", "like", "follow", "share", "gift", "stream_end"]
    user: str = "tester"
    text: str = ""
    count: int = 1
    gift_name: str = "Rose"
    diamonds: int = 1


def create_app(settings: Settings, source=None) -> FastAPI:
    hub = EventHub(settings.log_dir)
    norm = Normalizer(hub.publish, Moderator.from_file(settings.banned_words_file), settings.join_keywords)
    source = source or make_source(settings)

    async def supervise() -> None:
        try:
            await source.run(norm)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            source.status.connected = False
            source.status.last_error = f"source crashed: {exc}"
            log.exception("event source crashed")

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        task = asyncio.create_task(supervise())
        log.info("source %s started", source.status.name)
        yield
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)

    app = FastAPI(title="LiveBridge", lifespan=lifespan)
    app.state.hub = hub
    app.state.normalizer = norm
    app.state.source = source

    def authorized(token: str | None) -> bool:
        return not settings.token or secrets.compare_digest(token or "", settings.token)

    def require_token(token: str | None) -> None:
        if not authorized(token):
            raise HTTPException(status_code=401, detail="bad token")

    @app.get("/health")
    def health() -> dict:
        stats = hub.stats()
        return {
            "status": "ok",
            "source": source.status.name,
            "connected": source.status.connected,
            "last_error": source.status.last_error,
            "clients": stats["clients"],
            "last_event_age_s": stats["last_event_age_s"],
        }

    @app.get("/stats")
    def stats(token: str | None = Query(None)) -> dict:
        require_token(token)
        return hub.stats()

    @app.get("/events/recent")
    def recent(limit: int = Query(50, ge=1, le=200), token: str | None = Query(None)) -> list[dict]:
        require_token(token)
        return list(hub.recent)[-limit:]

    @app.post("/debug/event")
    def debug_event(event: DebugEvent, token: str | None = Query(None)) -> dict:
        """Inject a fake event, e.g. to test a big-gift animation on demand."""
        require_token(token)
        user = norm.viewer(f"debug-{event.user}", event.user)
        if event.type == "join":
            norm.comment(user, "!join")
        elif event.type == "comment":
            norm.comment(user, event.text)
        elif event.type == "like":
            norm.like(user, event.count)
        elif event.type == "follow":
            norm.follow(user)
        elif event.type == "share":
            norm.share(user)
        elif event.type == "gift":
            norm.gift(user, abs(hash(event.gift_name)) % 100000, event.gift_name, event.diamonds,
                      event.count, streak_ended=True)
        else:
            norm.stream_end()
        return {"ok": True}

    @app.websocket("/ws")
    async def ws(websocket: WebSocket, token: str | None = Query(None)) -> None:
        if not authorized(token):
            await websocket.close(code=1008)
            return
        await websocket.accept()
        queue = hub.subscribe()
        try:
            await websocket.send_json({"type": "hello", "source": source.status.name})
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=KEEPALIVE_S)
                except asyncio.TimeoutError:
                    event = {"type": "ping"}
                await websocket.send_json(event)
        except (WebSocketDisconnect, RuntimeError):
            pass
        finally:
            hub.unsubscribe(queue)

    return app
