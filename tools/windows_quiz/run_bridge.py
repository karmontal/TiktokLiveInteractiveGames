"""Starts LiveBridge in the standalone Windows quiz (copied next to bridge/livebridge by build.sh).

The game runs this with bridge/python/pythonw.exe and sets LIVEBRIDGE_SOURCE, TIKTOK_USERNAME,
LIVEBRIDGE_LOG_DIR and LIVEBRIDGE_BANNED_WORDS. There is no console, so output goes to
bridge/logs/bridge.log.
"""

import os
import runpy
import sys

here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "logs"), exist_ok=True)
log = open(os.path.join(here, "logs", "bridge.log"), "a", encoding="utf-8", buffering=1)
sys.stdout = sys.stderr = log
sys.path.insert(0, here)
os.chdir(here)
runpy.run_module("livebridge", run_name="__main__", alter_sys=True)
