# ألعاب Godot

مشروع Godot 4.5 (Compatibility renderer، 720×1280، 30fps). بيستقبل الأحداث من LiveBridge (`../bridge`) عبر WebSocket.

```
game/
├─ core/EventBus.gd       # WebSocket ← LiveBridge، وبيطلق إشارة event_received
├─ core/AvatarCache.gd    # تنزيل صور البروفايل وتخزينها ودوائر 64×64
├─ games/tug_of_war/      # شدّ الحبل: TugLogic.gd (القواعد) + TugOfWar.gd (الرسم)
├─ tests/run_tests.gd     # اختبارات القواعد بدون شاشة
└─ main.gd                # بيختار اللعبة (--game=tug_of_war)
```

## تشغيل على الماك

1. نزّل **Godot 4.5** (النسخة العادية، مش .NET) من godotengine.org.
2. شغّل LiveBridge (شوف `../bridge/README.md`) بالتوكن `test`.
3. افتح Godot ← Import ← اختار `game/project.godot` ← اضغط ▶ (أو F5).
4. النافذة بتطلع صغيرة (450×800) عشان تزبط على الشاشة، بس اللعبة جوّاها 720×1280.
5. بـ LIVE Studio ضيف مصدر **Window Capture** واختار نافذة اللعبة.

بدون بث ولا LiveBridge، بتقدر تجرّب بالكيبورد وإنت شغّال من المحرر:

| زر | الحدث |
|---|---|
| 1 | join (فريق تلقائي) |
| 2 / 3 | تعليق A / B |
| 4 | 10 لايكات |
| 5 | فولو |
| 6 | شير |
| 7 | وردة |
| 8 | هدية كبيرة (Corgi 299) |

الاتصال بـ LiveBridge: افتراضياً `ws://127.0.0.1:8765/ws` بالتوكن `test`. لتغييره:
`LIVEBRIDGE_WS=ws://... LIVEBRIDGE_TOKEN=... godot --path game` أو `godot --path game -- --bridge=ws://... --token=...`

## شدّ الحبل: القواعد

- تعليق `A` أو `B` (أو `أ`/`ب`، `1`/`2`) = تنضم أو تنقل لفريق.
- أي تفاعل من حدا بدون فريق بيحطّه بالفريق الأصغر تلقائياً، فكل لايك بيحسب.
- لايك = 0.004، فولو = 0.04، هدية = 0.01 لكل كوين بسقف 0.25، شير = قوة الفريق ×2 لـ 5 ثواني.
  (1.0 = المسافة من النص لخط الفوز، يعني تقريباً 250 لايك بتفوّز من النص.)
- الجولة 3 دقايق أو لحد ما فريق يوصل الخط. بعدها 8 ثواني نتيجة ونجم كل فريق، وجولة جديدة بأسماء فرق جديدة.
- الفرق بتضل محفوظة بين الجولات.

كل الأرقام بأول `games/tug_of_war/TugLogic.gd`، وبتتعدّل بعد ما نشوف البث الحقيقي.

## الاختبارات

```bash
godot --headless --path game --import
godot --headless --path game -s res://tests/run_tests.gd    # 21 passed, 0 failed
```

## الخط
Cairo (SIL Open Font License، `assets/fonts/OFL.txt`).
