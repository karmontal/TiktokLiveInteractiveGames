"""Reads a real TikTok LIVE through the unofficial TikTokLive library.

This is the only file that knows the library's API. If TikTok or the
library breaks, the fix (or a replacement library) goes here and nothing
else changes.
"""

from __future__ import annotations

import asyncio
import logging

from ..normalizer import Normalizer
from . import SourceStatus

log = logging.getLogger(__name__)

OFFLINE_RETRY_S = 60
ERROR_RETRY_S = 30


def _avatar(user) -> str:
    image = getattr(user, "avatar_thumb", None)
    urls = getattr(image, "m_urls", None) or getattr(image, "url_list", None) or []
    return urls[0] if urls else ""


class TikTokSource:
    def __init__(self, username: str, sign_api_key: str = ""):
        if not username:
            raise ValueError("TIKTOK_USERNAME is required when LIVEBRIDGE_SOURCE=tiktok")
        self.username = username
        self.sign_api_key = sign_api_key
        self.status = SourceStatus(name=f"tiktok:@{username}")

    def _build_client(self, norm: Normalizer):
        from TikTokLive import TikTokLiveClient
        from TikTokLive.events import (
            CommentEvent, ConnectEvent, DisconnectEvent, FollowEvent, GiftEvent,
            LikeEvent, LiveEndEvent, ShareEvent,
        )

        client = TikTokLiveClient(unique_id=self.username)

        def viewer(user):
            user_id = str(getattr(user, "id", "") or getattr(user, "display_id", ""))
            name = getattr(user, "nickname", "") or getattr(user, "display_id", "")
            return norm.viewer(user_id, name, _avatar(user))

        async def on_connect(event: ConnectEvent):
            self.status.connected = True
            self.status.last_error = ""
            log.info("connected to @%s (room %s)", event.unique_id, event.room_id)

        async def on_disconnect(_: DisconnectEvent):
            self.status.connected = False
            log.info("disconnected from @%s", self.username)

        async def on_comment(event: CommentEvent):
            norm.comment(viewer(event.user), event.content or "")

        async def on_like(event: LikeEvent):
            norm.like(viewer(event.user), event.count or 0)

        async def on_follow(event: FollowEvent):
            norm.follow(viewer(event.user))

        async def on_share(event: ShareEvent):
            norm.share(viewer(event.user))

        async def on_gift(event: GiftEvent):
            gift = event.gift
            if gift is None:
                return
            norm.gift(
                viewer(event.user),
                gift_id=int(gift.id),
                gift_name=gift.name or "Gift",
                diamonds=int(gift.diamond_count or 0),
                repeat_count=max(int(event.repeat_count or 1), 1),
                streak_ended=not event.streaking,
            )

        async def on_live_end(_: LiveEndEvent):
            norm.stream_end()

        for event_type, handler in [
            (ConnectEvent, on_connect), (DisconnectEvent, on_disconnect), (CommentEvent, on_comment),
            (LikeEvent, on_like), (FollowEvent, on_follow), (ShareEvent, on_share),
            (GiftEvent, on_gift), (LiveEndEvent, on_live_end),
        ]:
            client.add_listener(event_type, handler)
        return client

    async def run(self, norm: Normalizer) -> None:
        from TikTokLive.client.errors import UserOfflineError
        from TikTokLive.client.web.web_settings import WebDefaults

        if self.sign_api_key:
            WebDefaults.tiktok_sign_api_key = self.sign_api_key

        while True:
            client = self._build_client(norm)
            delay = ERROR_RETRY_S
            try:
                task = await client.start(fetch_room_info=False)
                await task
                log.info("stream connection closed, reconnecting")
            except asyncio.CancelledError:
                await client.disconnect(close_client=True)
                raise
            except UserOfflineError:
                self.status.last_error = "offline"
                delay = OFFLINE_RETRY_S
                log.info("@%s is not live, retrying in %ss", self.username, delay)
            except Exception as exc:  # the unofficial API fails in many ways; keep the bridge up
                self.status.last_error = f"{type(exc).__name__}: {exc}"
                log.warning("TikTok connection failed: %s, retrying in %ss", self.status.last_error, delay)
            self.status.connected = False
            try:
                await client.disconnect(close_client=True)
            except Exception:
                pass
            norm.reset_session()
            await asyncio.sleep(delay)
