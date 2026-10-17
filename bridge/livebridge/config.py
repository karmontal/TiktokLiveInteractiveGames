"""Settings, all from environment variables (see .env.example)."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from .normalizer import DEFAULT_JOIN_KEYWORDS


@dataclass(frozen=True)
class Settings:
    source: str = "mock"  # "mock" or "tiktok"
    tiktok_username: str = ""
    sign_api_key: str = ""
    token: str = ""  # required by /ws and /debug/event when set
    host: str = "127.0.0.1"
    port: int = 8765
    log_dir: Path | None = Path("logs")
    banned_words_file: Path | None = Path("banned_words.txt")
    join_keywords: tuple[str, ...] = DEFAULT_JOIN_KEYWORDS
    mock_rate: float = 3.0  # mock events per second

    @classmethod
    def from_env(cls) -> "Settings":
        env = os.environ.get
        keywords = env("LIVEBRIDGE_JOIN_KEYWORDS")
        log_dir = env("LIVEBRIDGE_LOG_DIR", "logs")
        return cls(
            source=env("LIVEBRIDGE_SOURCE", "mock").lower(),
            tiktok_username=env("TIKTOK_USERNAME", "").lstrip("@"),
            sign_api_key=env("TIKTOK_SIGN_API_KEY", ""),
            token=env("LIVEBRIDGE_TOKEN", ""),
            host=env("LIVEBRIDGE_HOST", "127.0.0.1"),
            port=int(env("LIVEBRIDGE_PORT", "8765")),
            log_dir=Path(log_dir) if log_dir else None,
            banned_words_file=Path(env("LIVEBRIDGE_BANNED_WORDS", "banned_words.txt")),
            join_keywords=tuple(k.strip() for k in keywords.split(",")) if keywords else DEFAULT_JOIN_KEYWORDS,
            mock_rate=float(env("LIVEBRIDGE_MOCK_RATE", "3")),
        )
