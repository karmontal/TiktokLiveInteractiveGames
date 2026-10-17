# TiktokLiveInteractiveGames

ألعاب تفاعلية لبث TikTok LIVE: المشاهدين بيلعبوا بالتعليقات واللايكات والفولو والشير والهدايا.

| المجلد | شو فيه |
|---|---|
| `bridge/` | LiveBridge: بيقرأ أحداث البث ويبعثها للعبة (Python) |
| `game/` | الألعاب (Godot 4.3+): شدّ الحبل، تحدّي المعلومات (عام وكورة) |
| `tools/make_music.py` | بيولّد موسيقى الخلفية (loops أصلية بدون حقوق) |
| `run-live.sh` | تشغيل كل شي بأمر واحد |

## التشغيل على الماك (أمر واحد)

```bash
./run-live.sh اسم_حسابك                  # تحدّي المعلومات، أسئلة عامة
./run-live.sh اسم_حسابك quiz football    # تحدّي الكورة
./run-live.sh اسم_حسابك tug_of_war       # شدّ الحبل
./run-live.sh mock quiz                  # تجربة بمشاهدين وهميين بدون TikTok
```

السكربت بيعمل كل شي لحاله: بيجهّز Python ومكتباته أول مرة، بيلاقي Godot بـ `/Applications`،
بيشغّل البريدج واللعبة ويعيد تشغيل أي واحد بيوقع، وبيخلّي الماك صاحي. **Ctrl+C** بيوقّف الكل.
بعدها بـ LIVE Studio: **Window Capture** ← نافذة Godot ← **Go LIVE**. السجلات بـ `logs/`.

التفاصيل: `bridge/README.md` و `game/README.md`. الخطة والأفكار: `tiktok-live-game-plan.md` و `tiktok-live-game-ideas.md`.
