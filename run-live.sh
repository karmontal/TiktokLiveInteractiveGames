#!/usr/bin/env bash
# One command to go live: starts LiveBridge and the Godot game, restarts either one
# if it stops, keeps the Mac awake, and stops everything on Ctrl+C.
#
#   ./run-live.sh <tiktok_username> [game] [pack]
#   ./run-live.sh mychannel                  # quiz, general questions
#   ./run-live.sh mychannel quiz football    # quiz, football questions
#   ./run-live.sh mychannel tug_of_war
#   ./run-live.sh mychannel climb
#   ./run-live.sh mock quiz                  # fake viewers, no TikTok needed
#
# Then in LIVE Studio: Window Capture -> the Godot window -> Go LIVE.
# Godot is looked up in /Applications and on PATH; set GODOT=/path/to/Godot to override.
# Logs: logs/bridge.log and logs/game.log

set -u
cd "$(dirname "$0")"
ROOT="$PWD"
USERNAME="${1:-}"
GAME="${2:-quiz}"
PACK="${3:-general}"
TOKEN="${LIVEBRIDGE_TOKEN:-test}"
LOGS="$ROOT/logs"
mkdir -p "$LOGS"

if [ -z "$USERNAME" ]; then
  echo "usage: ./run-live.sh <tiktok_username|mock> [quiz|tug_of_war|climb] [pack]"
  exit 1
fi
USERNAME="${USERNAME#@}"

# ---- Python environment for the bridge (created on first run, updated when requirements change)
VENV="$ROOT/bridge/.venv"
if [ ! -x "$VENV/bin/python" ]; then
  PY=""
  for candidate in python3.13 python3.12 python3.11 python3.10; do
    if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
  done
  if [ -z "$PY" ]; then
    echo "Python 3.10 or newer is needed. On the Mac: brew install python@3.12"
    exit 1
  fi
  echo "Creating bridge/.venv with $PY ..."
  "$PY" -m venv "$VENV" || exit 1
fi
REQ_SUM="$(cksum "$ROOT/bridge/requirements.txt" | cut -d' ' -f1)"
if [ "$(cat "$VENV/.requirements-sum" 2>/dev/null)" != "$REQ_SUM" ]; then
  echo "Installing bridge requirements ..."
  "$VENV/bin/pip" install -q -r "$ROOT/bridge/requirements.txt" || exit 1
  echo "$REQ_SUM" > "$VENV/.requirements-sum"
fi

# ---- Godot
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
  for candidate in /Applications/Godot*.app/Contents/MacOS/Godot; do
    if [ -x "$candidate" ]; then GODOT="$candidate"; break; fi
  done
fi
if [ -z "$GODOT" ] && command -v godot >/dev/null 2>&1; then GODOT="$(command -v godot)"; fi
if [ -z "$GODOT" ]; then
  echo "Godot not found. Put Godot.app in /Applications or run: GODOT=/path/to/Godot ./run-live.sh ..."
  exit 1
fi
if [ ! -d "$ROOT/game/.godot" ]; then
  echo "First run: importing the Godot project ..."
  "$GODOT" --headless --path "$ROOT/game" --editor --quit >>"$LOGS/game.log" 2>&1
fi

# ---- run and restart
keep_running() {   # keep_running <name> <log file> <command...>
  local name="$1" log="$2"
  shift 2
  while true; do
    echo "$(date '+%H:%M:%S') starting $name" >>"$log"
    "$@" >>"$log" 2>&1
    echo "$(date '+%H:%M:%S') $name stopped (exit $?), restarting in 3 s" | tee -a "$log"
    sleep 3
  done
}

cleanup() {
  trap - INT TERM EXIT
  echo
  echo "Stopping bridge and game ..."
  kill 0 2>/dev/null
}
trap cleanup INT TERM EXIT

SOURCE="tiktok @$USERNAME"
[ "$USERNAME" = "mock" ] && SOURCE="mock"

(
  cd "$ROOT/bridge"
  export LIVEBRIDGE_SOURCE="${SOURCE%% *}" TIKTOK_USERNAME="$USERNAME" LIVEBRIDGE_TOKEN="$TOKEN"
  keep_running bridge "$LOGS/bridge.log" "$VENV/bin/python" -m livebridge
) &

sleep 2
(
  export LIVEBRIDGE_TOKEN="$TOKEN"
  keep_running game "$LOGS/game.log" "$GODOT" --path "$ROOT/game" -- --game="$GAME" --pack="$PACK"
) &

if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dimsu -w $$ &                     # keep the Mac and the screen awake
fi

echo "Running: game=$GAME pack=$PACK source=$SOURCE"
echo "Logs:    logs/bridge.log  logs/game.log"
echo "Status:  http://127.0.0.1:8765/health   stats: http://127.0.0.1:8765/stats?token=$TOKEN"
echo "Stop:    Ctrl+C"
wait
