# LiveBridge: الـ Connector والـ Event API

بيقرأ أحداث بث TikTok LIVE (تعليقات، لايكات، فولو، شير، هدايا)، بينظّفها ويوحّد شكلها، وبيبعثها للعبة Godot عبر WebSocket.
هاد الجزء الأول من الخطة (`../tiktok-live-game-plan.md` القسم 2).

```
TikTok LIVE ─► sources/tiktok.py ─► normalizer.py ─► hub.py ─► /ws ─► Godot
               sources/mock.py ──┘   (قواعد + فلترة)   (توزيع + log)
```

## تشغيل محلي (بأحداث وهمية)

```bash
cd bridge
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
pytest                                   # 34 اختبار
LIVEBRIDGE_TOKEN=test python -m livebridge
```

بعدها:
- `http://127.0.0.1:8765/health`: حالة الاتصال
- `http://127.0.0.1:8765/stats?token=test`: أرقام البث (مشاهدين، منضمين، دايموندز)
- `ws://127.0.0.1:8765/ws?token=test`: هون بتتصل اللعبة

تجربة حدث معيّن (مثلاً هدية كبيرة عشان تجرّب أنيميشن):
```bash
curl -X POST "http://127.0.0.1:8765/debug/event?token=test" \
  -H 'Content-Type: application/json' \
  -d '{"type":"gift","user":"Omar","gift_name":"Lion","diamonds":29999,"count":1}'
```

## على بث حقيقي

بملف `.env` (انسخه من `.env.example`):
```
LIVEBRIDGE_SOURCE=tiktok
TIKTOK_USERNAME=اسم_حسابك_بدون_@
```
الحساب لازم يكون LIVE. إذا مش LIVE بيحاول كل 60 ثانية لحاله. أي بث عام بيشتغل، يعني بتقدر تجرّب على بث حساب ثاني قبل ما يصير عندك Stream Key.

## شكل الحدث اللي بيوصل للعبة

```json
{"type": "gift",
 "user": {"id": "6812...", "name": "Omar", "avatar": "https://...jpeg"},
 "count": 2,
 "gift": {"id": 6267, "name": "Corgi", "diamonds": 299, "tier": "large"},
 "value": 598,
 "ts": 1760000000.12}
```

| type | متى | حقول إضافية |
|---|---|---|
| `join` | تعليق بالضبط واحد من كلمات الدخول (`!join`، `join`، `دخول`، `ادخل`) | |
| `comment` | أي تعليق (بعد الفلترة). الألعاب بتقرأ منه `A`/`B` وغيرها | `text` |
| `like` | دفعة لايكات من مشاهد | `count` |
| `follow` | فولو، **مرة وحدة لكل مشاهد بالبث** (منع فولو/أنفولو) | |
| `share` | شير | |
| `gift` | هدية. بالـ streak بيوصل كل جزء جديد لحاله (x1 ثم x2...) بدون تكرار | `count`، `gift`، `value` |
| `stream_end` | البث خلص | |

رسائل تحكم: `{"type":"hello"}` أول ما تتصل، و `{"type":"ping"}` كل 15 ثانية إذا ما فيه أحداث.

**تصنيف الهدايا** حسب الخطة: `small` أقل من 10 كوين، `medium` من 10 لـ 99، `large` من 100 وفوق.

**شو مش هون:** أثر كل حدث (قديش اللايك بيشدّ الحبل مثلاً) بيتقرر جوّا كل لعبة، لأنه بيختلف من لعبة للثانية.

## النشر على السيرفر (Ubuntu)

```bash
sudo useradd --system --home /opt/livebridge livebridge
sudo git clone <repo> /opt/livebridge && cd /opt/livebridge/bridge
sudo python3 -m venv .venv && sudo .venv/bin/pip install -r requirements.txt
sudo cp .env.example .env && sudo nano .env      # حط TIKTOK_USERNAME و LIVEBRIDGE_TOKEN
sudo chown -R livebridge /opt/livebridge
sudo cp deploy/livebridge.service /etc/systemd/system/
sudo systemctl enable --now livebridge
journalctl -u livebridge -f                       # تتابع الـ log
```

`LIVEBRIDGE_HOST=127.0.0.1` معناها بس السيرفر نفسه بيقدر يتصل، وهاد المطلوب لأن Godot رح يشتغل على نفس السيرفر. ما تفتح البورت للإنترنت.

## ملاحظات
- **Redis:** الخطة كانت حاطة Redis. حالياً كله بعملية وحدة، فما في داعي إله. بنضيفه إذا صار عنا أكثر من عملية لازم تشارك نفس الأحداث.
- **سجل الأحداث:** كل حدث بينحفظ بـ `logs/events-YYYY-MM-DD.jsonl` (بتوقيت UTC). منه بنحسب نسبة المشاركين والدايموندز لكل ساعة (القسم 6 بالخطة).
- **المكتبة غير الرسمية:** `TikTokLive` بتعتمد على سيرفر توقيع خارجي (Euler Stream). إذا صار rate limit، سجّل مفتاح مجاني وحطه بـ `TIKTOK_SIGN_API_KEY`. كل الكود اللي بيعرف المكتبة موجود بملف واحد: `sources/tiktok.py`.
