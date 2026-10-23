#!/usr/bin/env bash
# Builds the standalone Windows quiz that anyone can unzip and run, no installs needed:
#   build/windows-quiz/QuizGame.exe         the quiz (Godot, opens with launcher/Launcher.gd)
#   build/windows-quiz/bridge/              LiveBridge with its own Windows Python
#   build/TikTokQuiz-windows.zip
# Runs on Linux or macOS. Needs Godot 4.3 (GODOT=/path/to/godot), python3, and access to
# nuget.org (Windows Python), pypi.org (packages) and github.com (Godot's Windows template).
#
#   tools/windows_quiz/build.sh

set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
HERE="$ROOT/tools/windows_quiz"
OUT="$ROOT/build/windows-quiz"
CACHE="$ROOT/build/cache"
PY_VERSION="3.12.10"
GODOT_VERSION="4.3"
SDIST_ONLY=(protobuf3-to-dict)          # pure Python, published without wheels: built here
GODOT="${GODOT:-$(command -v godot || true)}"
[ -x "$GODOT" ] || { echo "Godot $GODOT_VERSION not found: GODOT=/path/to/godot $0"; exit 1; }

rm -rf "$OUT" "$ROOT/build/TikTokQuiz-windows.zip"
mkdir -p "$OUT/bridge" "$CACHE/wheels"

echo "== Windows Python $PY_VERSION (NuGet)"
NUPKG="$CACHE/python.$PY_VERSION.nupkg"
[ -f "$NUPKG" ] || curl -sSfL -o "$NUPKG" "https://api.nuget.org/v3-flatcontainer/python/$PY_VERSION/python.$PY_VERSION.nupkg"
python3 -I - "$NUPKG" "$OUT/bridge/python" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for info in z.infolist():
    if info.filename.startswith("tools/") and not info.is_dir():
        info.filename = info.filename[len("tools/"):]
        z.extract(info, sys.argv[2])
PY
for unused in test idlelib tkinter turtledemo; do rm -rf "$OUT/bridge/python/Lib/$unused"; done

echo "== bridge packages for Windows"
if [ ! -x "$CACHE/uv/bin/uv" ]; then
  python3 -m pip install -q --target "$CACHE/uv" uv
fi
for pkg in "${SDIST_ONLY[@]}"; do
  ls "$CACHE/wheels/$(echo "$pkg" | tr - _)"-*.whl >/dev/null 2>&1 || python3 -m pip wheel -q --no-deps "$pkg" -w "$CACHE/wheels"
done
PYTHONPATH="$CACHE/uv" "$CACHE/uv/bin/uv" pip install -q --target "$OUT/bridge/python/Lib/site-packages" \
  --python-platform x86_64-pc-windows-msvc --python-version 3.12 --find-links "$CACHE/wheels" \
  -r "$ROOT/bridge/requirements.txt"

echo "== LiveBridge"
cp -r "$ROOT/bridge/livebridge" "$OUT/bridge/"
find "$OUT/bridge/livebridge" -name __pycache__ -prune -exec rm -rf {} +
cp "$ROOT/bridge/banned_words.txt" "$HERE/run_bridge.py" "$OUT/bridge/"

echo "== Godot $GODOT_VERSION Windows template"
TEMPLATES="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$GODOT_VERSION.stable"
[ "$(uname)" = "Darwin" ] && TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION.stable"
if [ ! -f "$TEMPLATES/windows_release_x86_64.exe" ]; then
  mkdir -p "$TEMPLATES"
  # Only the one file out of the 1 GB archive, with HTTP range requests.
  python3 -I "$HERE/remote_unzip.py" \
    "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION-stable/Godot_v$GODOT_VERSION-stable_export_templates.tpz" \
    "$TEMPLATES" templates/windows_release_x86_64.exe templates/version.txt
fi

echo "== QuizGame.exe"
"$GODOT" --headless --path "$ROOT/game" --editor --quit >/dev/null 2>&1 || true     # import assets
"$GODOT" --headless --path "$ROOT/game" --export-release "Windows Quiz" "$OUT/QuizGame.exe"
[ -f "$OUT/QuizGame.exe" ] || { echo "export failed"; exit 1; }
cp "$HERE/README-windows.txt" "$OUT/اقرأني.txt"

echo "== zip"
python3 -I - "$OUT" "$ROOT/build/TikTokQuiz-windows.zip" <<'PY'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for folder, _, files in os.walk(src):
        for f in files:
            path = os.path.join(folder, f)
            z.write(path, os.path.join("TikTokQuiz", os.path.relpath(path, src)))
PY
ls -lh "$ROOT/build/TikTokQuiz-windows.zip"
