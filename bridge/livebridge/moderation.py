"""Name and comment filtering before anything reaches the screen."""

from __future__ import annotations

import re
import unicodedata
from pathlib import Path

MAX_NAME_LEN = 20
MAX_TEXT_LEN = 120

# Arabic diacritics and tatweel, so "كـــلب" and "كَلْب" match "كلب".
_ARABIC_MARKS = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ]")
_CONTROL = re.compile(r"[\u0000-\u001F\u007F​-‏‪-‮⁦-⁩]")


def _fold(text: str) -> str:
    text = unicodedata.normalize("NFKC", text).casefold()
    text = _ARABIC_MARKS.sub("", text)
    return text.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا").replace("ة", "ه").replace("ى", "ي")


class Moderator:
    def __init__(self, banned_words: list[str]):
        self._banned = [_fold(w) for w in banned_words if w.strip()]

    @classmethod
    def from_file(cls, path: str | Path | None) -> "Moderator":
        if not path or not Path(path).exists():
            return cls([])
        lines = Path(path).read_text(encoding="utf-8").splitlines()
        return cls([ln.strip() for ln in lines if ln.strip() and not ln.startswith("#")])

    def is_clean(self, text: str) -> bool:
        folded = _fold(text)
        return not any(word in folded for word in self._banned)

    def clean_name(self, name: str, fallback_id: str) -> str:
        name = _CONTROL.sub("", name).strip()[:MAX_NAME_LEN]
        if not name or not self.is_clean(name):
            return f"Player{fallback_id[-4:]}"
        return name

    def clean_text(self, text: str) -> str | None:
        """Return the text safe for display, or None if it must not be shown."""
        text = _CONTROL.sub("", text).strip()[:MAX_TEXT_LEN]
        if not self.is_clean(text):
            return None
        return text
