import asyncio

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from livebridge.app import create_app
from livebridge.config import Settings
from livebridge.normalizer import Normalizer
from livebridge.sources import SourceStatus
from livebridge.sources.mock import MockSource

TOKEN = "secret"


class IdleSource:
    def __init__(self):
        self.status = SourceStatus(name="idle", connected=True)

    async def run(self, norm):
        await asyncio.Event().wait()


@pytest.fixture
def client(tmp_path):
    settings = Settings(token=TOKEN, log_dir=tmp_path, banned_words_file=None)
    with TestClient(create_app(settings, source=IdleSource())) as c:
        yield c


def test_health_is_public(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["source"] == "idle"
    assert body["connected"] is True


def test_overlay_page_is_served(client):
    resp = client.get("/overlay/test.html")
    assert resp.status_code == 200
    assert "/ws?token=" in resp.text


def test_stats_needs_token(client):
    assert client.get("/stats").status_code == 401
    assert client.get("/stats", params={"token": TOKEN}).status_code == 200


def test_ws_rejects_bad_token(client):
    with pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws?token=wrong") as ws:
            ws.receive_json()


def test_ws_receives_injected_events(client):
    with client.websocket_connect(f"/ws?token={TOKEN}") as ws:
        assert ws.receive_json()["type"] == "hello"
        resp = client.post(f"/debug/event?token={TOKEN}",
                           json={"type": "gift", "user": "Omar", "gift_name": "Corgi", "diamonds": 299, "count": 2})
        assert resp.status_code == 200
        event = ws.receive_json()
    assert event["type"] == "gift"
    assert event["user"]["name"] == "Omar"
    assert event["gift"]["tier"] == "large"
    assert event["value"] == 598


def test_debug_join_goes_through_join_rule(client):
    with client.websocket_connect(f"/ws?token={TOKEN}") as ws:
        ws.receive_json()
        client.post(f"/debug/event?token={TOKEN}", json={"type": "join", "user": "Lina"})
        assert ws.receive_json()["type"] == "join"
        assert ws.receive_json()["type"] == "comment"
    recent = client.get("/events/recent", params={"token": TOKEN}).json()
    assert [e["type"] for e in recent] == ["join", "comment"]


def test_mock_source_produces_valid_events():
    events = []
    norm = Normalizer(events.append)
    source = MockSource(seed=1)
    for _ in range(300):
        source.step(norm)
    types = {e.type for e in events}
    assert {"join", "comment", "like", "gift"} <= types
    assert all(e.user and e.user.name for e in events)


def test_tiktok_source_registers_handlers():
    pytest.importorskip("TikTokLive")
    from livebridge.sources.tiktok import TikTokSource
    client = TikTokSource("someone")._build_client(Normalizer(lambda e: None))
    assert client.unique_id == "someone"
