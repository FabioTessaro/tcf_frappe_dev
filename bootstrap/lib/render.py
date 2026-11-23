#!/usr/bin/env python3
"""Render a frappe-dev template.

Usage:  render.py TEMPLATE TARGET [--mode 600] [--backup-dir DIR] [--check]
Values: NUL-separated KEY=VALUE pairs on stdin (never on the command line, so
        secrets don't show up in `ps`).

Template syntax
  @@KEY@@                 replaced by the value of KEY (must be provided).
  @@IF KEY@@ ... @@ENDIF KEY@@
                          the lines in between are kept only when KEY is set to
                          a "true" value (anything except "", 0, false, no).
  @@IFNOT KEY@@ ... @@ENDIF KEY@@
                          the opposite.
  @@# comment             line removed from the output.
Marker lines (IF/IFNOT/ENDIF) are removed entirely. Blocks can be nested.

Prints one of: created / updated / unchanged, followed by the target path.
With --check nothing is written and the exit code is 0 (unchanged) or 3
(would change). An existing target that changes is copied into --backup-dir
(or TARGET.bak when no directory is given) first.
"""

import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

FALSY = {"", "0", "false", "no", "off"}


def parse_args(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    opts = {
        "template": Path(argv[1]),
        "target": Path(argv[2]),
        "mode": None,
        "backup_dir": None,
        "check": False,
    }
    i = 3
    while i < len(argv):
        arg = argv[i]
        if arg == "--mode":
            opts["mode"] = int(argv[i + 1], 8)
            i += 2
        elif arg == "--backup-dir":
            opts["backup_dir"] = Path(argv[i + 1])
            i += 2
        elif arg == "--check":
            opts["check"] = True
            i += 1
        else:
            raise SystemExit(f"render.py: unknown option {arg}")
    return opts


def read_values():
    raw = sys.stdin.buffer.read().decode("utf-8")
    values = {}
    for item in raw.split("\0"):
        if not item:
            continue
        key, sep, value = item.partition("=")
        if not sep or not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            raise SystemExit(f"render.py: invalid value name {key!r}")
        values[key] = value
    return values


def render(text, values, source):
    out = []
    stack = []  # (key, keep)
    marker = re.compile(r"^\s*@@(IF|IFNOT|ENDIF) ([A-Z][A-Z0-9_]*)@@\s*$")
    for lineno, line in enumerate(text.splitlines(keepends=True), 1):
        m = marker.match(line)
        if m:
            kind, key = m.groups()
            if kind == "ENDIF":
                if not stack or stack[-1][0] != key:
                    raise SystemExit(f"{source}:{lineno}: unexpected @@ENDIF {key}@@")
                stack.pop()
            else:
                if key not in values:
                    raise SystemExit(f"{source}:{lineno}: condition {key} has no value")
                truthy = values[key].strip().lower() not in FALSY
                stack.append((key, truthy if kind == "IF" else not truthy))
            continue
        if line.lstrip().startswith("@@#"):
            continue
        if all(keep for _, keep in stack):
            out.append(line)
    if stack:
        raise SystemExit(f"{source}: unclosed @@IF {stack[-1][0]}@@")

    content = "".join(out)

    def sub(match):
        key = match.group(1)
        if key not in values:
            raise SystemExit(f"{source}: no value for placeholder @@{key}@@")
        return values[key]

    return re.sub(r"@@([A-Z][A-Z0-9_]*)@@", sub, content)


def main():
    opts = parse_args(sys.argv)
    template, target = opts["template"], opts["target"]
    if not template.is_file():
        raise SystemExit(f"render.py: template not found: {template}")
    content = render(template.read_text(encoding="utf-8"), read_values(), template)

    exists = target.is_file()
    if exists and target.read_text(encoding="utf-8") == content:
        print(f"unchanged: {target}")
        return 0
    if opts["check"]:
        print(f"{'updated' if exists else 'created'} (dry run): {target}")
        return 3

    target.parent.mkdir(parents=True, exist_ok=True)
    if exists:
        mode = target.stat().st_mode & 0o777
        if opts["backup_dir"]:
            opts["backup_dir"].mkdir(parents=True, exist_ok=True)
            stamp = time.strftime("%Y%m%d-%H%M%S")
            backup = opts["backup_dir"] / f"{target.name}.{stamp}"
        else:
            backup = target.with_name(target.name + ".bak")
        shutil.copy2(target, backup)
        os.chmod(backup, mode)
        if opts["backup_dir"]:
            # Keep the 10 most recent backups of this file.
            old = sorted(
                opts["backup_dir"].glob(f"{target.name}.*"), key=lambda f: f.stat().st_mtime
            )
            for stale in old[:-10]:
                stale.unlink()
        status = "updated"
    else:
        mode = 0o644
        status = "created"
    if opts["mode"] is not None:
        mode = opts["mode"]

    fd, tmp = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(content)
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise
    print(f"{status}: {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
