"""The release rules for a changelog: python tools/release_check.py docs/releases/0.1.0.md

A changelog is a list, one change per line ("- Added ..."), with nothing else in it, and follows the
rules for public text: no em or en dashes, no possessive "its", no first or second person.
"""

import re
import sys

WORDS = re.compile(r"\b(its|it's|i|me|my|we|our|us|you|your)\b", re.I)


def check(text):
    problems = []
    entries = [s.strip() for s in text.replace("\r", "").split("\n") if s.strip()]
    if not entries:
        problems.append("the changelog is empty")
    for s in entries:
        if not s.startswith("- ") or len(s) < 3:
            problems.append(f"not a list entry (one change per line, starting with \"- \"): {s}")
            continue
        if "—" in s or "–" in s:
            problems.append(f"em or en dash: {s}")
        m = WORDS.search(s)
        if m:
            problems.append(f"\"{m.group(0)}\": {s}")
    return problems


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        found = check(f.read())
    for p in found:
        print(p)
    sys.exit(1 if found else 0)
