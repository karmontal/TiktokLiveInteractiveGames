import asyncio
import json

from livebridge.events import LiveEvent, Viewer
from livebridge.hub import EventHub

OMAR = Viewer("1", "Omar")


def test_subscriber_receives_events():
    async def scenario():
        hub = EventHub()
        queue = hub.subscribe()
        hub.publish(LiveEvent("follow", OMAR))
        return await asyncio.wait_for(queue.get(), 1)

    assert asyncio.run(scenario())["type"] == "follow"


def test_slow_subscriber_drops_oldest():
    async def scenario():
        hub = EventHub(queue_size=2)
        queue = hub.subscribe()
        for n in (1, 2, 3):
            hub.publish(LiveEvent("like", OMAR, count=n))
        return [queue.get_nowait()["count"] for _ in range(queue.qsize())]

    assert asyncio.run(scenario()) == [2, 3]


def test_unsubscribe_stops_delivery():
    async def scenario():
        hub = EventHub()
        queue = hub.subscribe()
        hub.unsubscribe(queue)
        hub.publish(LiveEvent("share", OMAR))
        return queue.qsize(), hub.client_count

    assert asyncio.run(scenario()) == (0, 0)


def test_stats():
    hub = EventHub()
    hub.publish(LiveEvent("join", OMAR))
    hub.publish(LiveEvent("like", Viewer("2", "Lina"), count=5))
    hub.publish(LiveEvent("gift", OMAR, count=2, value=10))
    stats = hub.stats()
    assert stats["unique_viewers"] == 2
    assert stats["joined_viewers"] == 1
    assert stats["diamonds"] == 10
    assert stats["events"] == {"join": 1, "like": 1, "gift": 1}


def test_jsonl_log(tmp_path):
    hub = EventHub(log_dir=tmp_path)
    hub.publish(LiveEvent("comment", Viewer("1", "عمر"), text="مرحبا", ts=1760000000))
    (log_file,) = tmp_path.glob("events-*.jsonl")
    assert log_file.name == "events-2025-10-09.jsonl"
    assert json.loads(log_file.read_text(encoding="utf-8"))["text"] == "مرحبا"
