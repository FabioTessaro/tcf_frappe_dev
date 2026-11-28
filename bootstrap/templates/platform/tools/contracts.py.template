#!/usr/bin/env python3
"""Platform contract checks across apps (`just test-platform`, guide 403).

Usage: contracts.py APPS_DIR LOCK

APPS_DIR holds a checkout of every app of the lock (`lock.py checkout`).
Checks, per app, without importing any app code:

  SYS-APP-001  app and module names valid, no clash with Frappe modules
  SYS-DEP-001  required_apps lists the core app
  SYS-DEP-002  core_sdk_version declared, and the locked core sdk inside it
  SYS-DEP-003  the required_apps graph is acyclic
  SYS-DEP-006  no Link field to a doctype of an app outside required_apps
  CT-REG-003   portal_apps hook id equals the frontend manifest id
"""

from __future__ import annotations

import ast
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lock as lockfile  # noqa: E402

FRAPPE_MODULES = {"core", "desk", "website", "email", "integrations", "automation"}
NAME = re.compile(r"^[a-z][a-z0-9_]*$")
VERSION = re.compile(r"^\s*v?(\d+)\.(\d+)(?:\.(\d+))?\s*$")


def hooks(app_dir: Path, app: str) -> dict[str, object]:
    path = app_dir / app / "hooks.py"
    values: dict[str, object] = {}
    if not path.is_file():
        return values
    for node in ast.parse(path.read_text(encoding="utf-8")).body:
        # `name = value` and `name: type = value` (type-checked hooks).
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target, value = node.targets[0], node.value
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            target, value = node.target, node.value
        else:
            continue
        if isinstance(target, ast.Name):
            try:
                values[target.id] = ast.literal_eval(value)
            except ValueError:
                continue
    return values


def parse_version(text: str) -> tuple[int, int, int] | None:
    m = VERSION.match(text)
    return (int(m[1]), int(m[2]), int(m[3] or 0)) if m else None


def in_range(version: tuple[int, int, int], spec: str) -> bool:
    for part in spec.split(","):
        m = re.match(r"^\s*(>=|<=|==|>|<)\s*([\d.]+)\s*$", part)
        if not m:
            return False
        bound = parse_version(m[2])
        if bound is None:
            return False
        ok = {
            ">=": version >= bound,
            "<=": version <= bound,
            "==": version == bound,
            ">": version > bound,
            "<": version < bound,
        }[m[1]]
        if not ok:
            return False
    return True


def cycle(graph: dict[str, list[str]]) -> list[str]:
    state: dict[str, int] = {}
    path: list[str] = []

    def visit(node: str) -> list[str]:
        state[node] = 1
        path.append(node)
        for nxt in graph.get(node, []):
            if state.get(nxt) == 1:
                return [*path[path.index(nxt) :], nxt]
            if nxt in graph and not state.get(nxt):
                found = visit(nxt)
                if found:
                    return found
        path.pop()
        state[node] = 2
        return []

    for node in graph:
        if not state.get(node):
            found = visit(node)
            if found:
                return found
    return []


def doctype_owners(apps_dir: Path, names: list[str]) -> dict[str, str]:
    owners: dict[str, str] = {}
    for app in names:
        for path in (apps_dir / app / app).glob("*/doctype/*/*.json"):
            if path.stem == path.parent.name:
                data = json.loads(path.read_text(encoding="utf-8"))
                if data.get("doctype") == "DocType" and data.get("name"):
                    owners[data["name"]] = app
    return owners


def check(apps_dir: Path, lock: dict[str, dict[str, str]]) -> list[str]:
    names = lockfile.apps(lock)
    core = next((n for n in names if lock[n].get("kind") == "core"), None)
    found: list[str] = []
    graph: dict[str, list[str]] = {}
    core_version = parse_version(lock[core]["version"]) if core else None
    meta = {app: hooks(apps_dir / app, app) for app in names}
    if core:
        # In the core app, core_sdk_version is the version it provides (e.g. "0.1.0").
        sdk = meta[core].get("core_sdk_version")
        if isinstance(sdk, str):
            core_version = parse_version(sdk)
    for app in names:
        h = meta[app]
        if app in FRAPPE_MODULES:
            found.append(f"{app}: SYS-APP-001 app name clashes with a Frappe module")
        modules = apps_dir / app / app / "modules.txt"
        if modules.is_file():
            for module in modules.read_text(encoding="utf-8").splitlines():
                slug = module.strip().lower().replace(" ", "_")
                if slug in FRAPPE_MODULES:
                    found.append(f"{app}: SYS-APP-001 module '{module}' clashes with Frappe")
        required = h.get("required_apps", [])
        required = [r for r in required if isinstance(r, str)] if isinstance(required, list) else []
        graph[app] = required
        if app != core:
            if core and core not in required:
                found.append(f"{app}: SYS-DEP-001 required_apps must list {core}")
            spec = h.get("core_sdk_version")
            if not isinstance(spec, str):
                found.append(f"{app}: SYS-DEP-002 core_sdk_version is not declared")
            elif core_version and not in_range(core_version, spec):
                found.append(f"{app}: SYS-DEP-002 core sdk {core_version} outside '{spec}'")
        portal = h.get("portal_apps")
        manifest = apps_dir / app / "frontend" / "manifest.ts"
        if isinstance(portal, list) and manifest.is_file():
            ids = re.findall(r"\bid:\s*[\"']([^\"']+)[\"']", manifest.read_text(encoding="utf-8"))
            for entry in portal:
                if isinstance(entry, dict) and entry.get("id") not in ids:
                    found.append(f"{app}: CT-REG-003 hook id {entry.get('id')!r} not in manifest")
    loop = cycle(graph)
    if loop:
        found.append(f"SYS-DEP-003 dependency cycle: {' -> '.join(loop)}")
    owners = doctype_owners(apps_dir, names)
    for app in names:
        allowed = {app, "frappe", *graph[app]}
        for path in (apps_dir / app / app).glob("*/doctype/*/*.json"):
            if path.stem != path.parent.name:
                continue
            for field in json.loads(path.read_text(encoding="utf-8")).get("fields", []):
                target = field.get("options") if field.get("fieldtype") == "Link" else None
                owner = owners.get(target or "")
                if owner and owner not in allowed:
                    found.append(
                        f"{app}: SYS-DEP-006 {path.stem}.{field.get('fieldname')} "
                        f"links to {target} of {owner} (not in required_apps)"
                    )
    return found


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    lock = lockfile.load(Path(argv[2]))
    found = check(Path(argv[1]), lock)
    for line in found:
        print(line, file=sys.stderr)
    if not found:
        print(f"platform contracts: ok ({len(lockfile.apps(lock))} app(s))")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
