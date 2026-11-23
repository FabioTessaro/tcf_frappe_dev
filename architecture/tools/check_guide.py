#!/usr/bin/env python3
"""Consistency check of the architecture guide (FND-READ-001).

- every rule ID is defined exactly once;
- every rule ID referenced in the text is defined somewhere;
- every relative link between Markdown files points to an existing file.

Usage: check_guide.py [GUIDE_DIR [EXTRA_MARKDOWN ...]]
       (defaults: architecture/ and README.md, relative to the repository root)
Exit code 1 when a problem is found.
"""

import re
import sys
import urllib.parse
from collections import defaultdict
from pathlib import Path

PREFIXES = "FND|SYS|DOM|CT|FE|BE|SEC|TST|DEL|OPS|CMP"
RULE_ID = re.compile(rf"\b(?:{PREFIXES})-[A-Z0-9]+-\d{{3}}\b")
RULE_DEF = re.compile(rf"^\s*-\s+`((?:{PREFIXES})-[A-Z0-9]+-\d{{3}})`", re.MULTILINE)
LINK = re.compile(r"\]\(([^)#\s]+)(#[^)]*)?\)")


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    guide = Path(sys.argv[1]) if len(sys.argv) > 1 else repo / "architecture"
    extra = [Path(p) for p in sys.argv[2:]] or [repo / "README.md"]
    files = sorted(p for p in guide.rglob("*.md") if "dist" not in p.parts) + extra

    defined: dict[str, list[str]] = defaultdict(list)
    referenced: set[str] = set()
    broken: list[str] = []
    for f in files:
        text = f.read_text(encoding="utf-8")
        for m in RULE_DEF.finditer(text):
            defined[m.group(1)].append(str(f.relative_to(repo)))
        referenced.update(RULE_ID.findall(text))
        for m in LINK.finditer(text):
            target = m.group(1)
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            if not (f.parent / urllib.parse.unquote(target)).exists():
                broken.append(f"{f.relative_to(repo)}: {target}")

    problems = [
        f"duplicate rule ID {k}: {', '.join(v)}" for k, v in sorted(defined.items()) if len(v) > 1
    ]
    problems += [
        f"rule ID referenced but not defined: {r}" for r in sorted(referenced - set(defined))
    ]
    problems += [f"broken link: {b}" for b in broken]

    for p in problems:
        print(p)
    print(f"{len(files)} files, {len(defined)} rule IDs, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
