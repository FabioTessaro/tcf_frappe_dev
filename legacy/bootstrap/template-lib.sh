#!/usr/bin/env bash
# Shared helpers for rendering repository-owned templates.
# Source this file; it intentionally performs no work on import.

render_template() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: render_template TEMPLATE TARGET [KEY=VALUE ...]" >&2
    return 2
  fi

  local template="$1" target="$2"
  shift 2
  [[ -f "$template" ]] || { echo "Template not found: $template" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required to render templates." >&2
    return 1
  }

  python3 - "$template" "$target" "$@" <<'PY'
from pathlib import Path
import os
import re
import shutil
import sys
import tempfile

source = Path(sys.argv[1])
target = Path(sys.argv[2])
content = source.read_text(encoding="utf-8")

for item in sys.argv[3:]:
    key, separator, value = item.partition("=")
    if not separator or not re.fullmatch(r"[A-Z0-9_]+", key):
        raise SystemExit(f"Invalid template value: {item!r}")
    content = content.replace(f"@@{key}@@", value)

unresolved = sorted(set(re.findall(r"@@[A-Z0-9_]+@@", content)))
if unresolved:
    raise SystemExit(f"Unresolved template placeholders in {source}: {', '.join(unresolved)}")

target.parent.mkdir(parents=True, exist_ok=True)
if target.is_file() and target.read_text(encoding="utf-8") == content:
    print(f"unchanged: {target}")
    raise SystemExit(0)

if target.exists():
    backup = target.with_name(target.name + ".bak")
    shutil.copy2(target, backup)
    mode = target.stat().st_mode & 0o777
    status = "updated"
else:
    mode = 0o644
    status = "created"

fd, temporary = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
        stream.write(content)
    os.chmod(temporary, mode)
    os.replace(temporary, target)
except Exception:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
print(f"{status}: {target}")
PY
}

append_template_block() {
  if [[ $# -ne 3 ]]; then
    echo "Usage: append_template_block TEMPLATE TARGET MARKER" >&2
    return 2
  fi

  local template="$1" target="$2" marker="$3"
  [[ -f "$template" ]] || { echo "Template not found: $template" >&2; return 1; }
  mkdir -p "$(dirname "$target")"

  if [[ -f "$target" ]] && grep -Fq -- "$marker" "$target"; then
    echo "unchanged: $target already contains $marker"
    return 0
  fi

  if [[ -f "$target" && -s "$target" ]]; then
    [[ "$(tail -c 1 "$target" | wc -l)" -gt 0 ]] || printf '\n' >> "$target"
    cat "$template" >> "$target"
    echo "updated: $target"
  else
    cp "$template" "$target"
    echo "created: $target"
  fi
}
