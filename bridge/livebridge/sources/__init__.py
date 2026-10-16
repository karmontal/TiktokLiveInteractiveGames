"""Event sources. Each one runs forever and feeds a Normalizer."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class SourceStatus:
    name: str
    connected: bool = False
    last_error: str = ""
