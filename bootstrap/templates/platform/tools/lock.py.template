#!/usr/bin/env python3
"""platform.lock: read, check and use the single definition of a release.

Usage: lock.py COMMAND LOCK [ARGS]

  check LOCK [--remote]      validate the structure; with --remote also check
                             that every tag exists and points to the locked
                             commit (needs network; APPS_READ_TOKEN for
                             private repositories)
  apps LOCK                  app names except frappe, one per line
  core LOCK                  name of the core app, or nothing
  frappe-env LOCK            FRAPPE_REPOSITORY=… FRAPPE_VERSION=… (shell)
  apps-json LOCK             apps.json for `bench init --apps_path`
  verify-bench LOCK BENCH    every app of the bench is at its locked commit
  checkout LOCK DIR          shallow clone of every app at its locked tag

Entries: [frappe] and one table per app with repository, version, commit and,
for apps, kind (core | foundation | feature | site). Lock rules: guide 500.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess  # noqa: S404 - git is called with fixed arguments
import sys
import tomllib
from pathlib import Path

APP_NAME = re.compile(r"^[a-z][a-z0-9_]*$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
KINDS = {"core", "foundation", "feature", "site"}


class LockError(Exception):
    pass


def load(path: Path) -> dict[str, dict[str, str]]:
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise LockError(f"{path}: {exc}") from exc
    return {name: dict(entry) for name, entry in data.items()}


def problems(lock: dict[str, dict[str, str]]) -> list[str]:
    found: list[str] = []
    if "frappe" not in lock:
        found.append("[frappe] is missing")
    cores = [n for n, e in lock.items() if e.get("kind") == "core"]
    if len(cores) > 1:
        found.append(f"more than one core app: {', '.join(cores)}")
    for name, entry in lock.items():
        if not APP_NAME.match(name):
            found.append(f"[{name}]: invalid app name (SYS-APP-001)")
        for key in ("repository", "version", "commit"):
            if not isinstance(entry.get(key), str) or not entry[key]:
                found.append(f"[{name}]: '{key}' is missing")
        if entry.get("commit") and not COMMIT.match(entry["commit"]):
            found.append(f"[{name}]: commit must be a 40-character SHA")
        if name != "frappe" and entry.get("kind") not in KINDS:
            found.append(f"[{name}]: kind must be one of {', '.join(sorted(KINDS))}")
        keys = list(entry)
        if {"repository", "version", "commit"} <= set(keys):
            i = keys.index("repository")
            if keys[i : i + 3] != ["repository", "version", "commit"]:
                found.append(
                    f"[{name}]: repository, version and commit must be consecutive,"
                    " in this order (Renovate)"
                )
        if entry.get("repository", "").startswith("git@"):
            found.append(f"[{name}]: use an https:// repository URL (CI and image builds)")
    return found


def apps(lock: dict[str, dict[str, str]]) -> list[str]:
    return [name for name in lock if name != "frappe"]


def _authed(url: str) -> str:
    token = os.environ.get("APPS_READ_TOKEN", "")
    if token and url.startswith("https://github.com/"):
        return url.replace("https://", f"https://x-access-token:{token}@", 1)
    return url


def _git(*args: str, cwd: Path | None = None) -> str:
    result = subprocess.run(  # noqa: S603 - fixed git subcommands
        ["git", *args],  # noqa: S607 - git from PATH (CI image / dev environment)
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise LockError(f"git {' '.join(args[:2])}: {result.stderr.strip()}")
    return result.stdout


def remote_commit(url: str, tag: str) -> str:
    out = _git("ls-remote", _authed(url), f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}")
    refs: dict[str, str] = {}
    for line in out.splitlines():
        sha, _, ref = line.partition("\t")
        if ref:
            refs[ref] = sha
    commit = refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}")
    if not commit:
        raise LockError(f"tag {tag} not found in {url}")
    return commit


def cmd_check(lock_path: Path, remote: bool) -> int:
    lock = load(lock_path)
    found = problems(lock)
    if remote and not found:
        for name, entry in lock.items():
            try:
                sha = remote_commit(entry["repository"], entry["version"])
            except LockError as exc:
                found.append(f"[{name}]: {exc}")
                continue
            if sha != entry["commit"]:
                found.append(f"[{name}]: {entry['version']} is {sha}, lock says {entry['commit']}")
    for line in found:
        print(f"platform.lock: {line}", file=sys.stderr)
    if not found:
        print(f"platform.lock: ok (frappe + {len(apps(lock))} app(s))")
    return 1 if found else 0


def cmd_verify_bench(lock_path: Path, bench: Path) -> int:
    lock = load(lock_path)
    bad = 0
    for name, entry in lock.items():
        head = _git("rev-parse", "HEAD", cwd=bench / "apps" / name).strip()
        if head != entry["commit"]:
            print(f"{name}: at {head}, lock says {entry['commit']}", file=sys.stderr)
            bad += 1
    return 1 if bad else 0


def cmd_checkout(lock_path: Path, target: Path) -> int:
    lock = load(lock_path)
    target.mkdir(parents=True, exist_ok=True)
    for name in apps(lock):
        entry, dest = lock[name], target / name
        if not dest.exists():
            _git(
                "clone",
                "--quiet",
                "--depth",
                "1",
                "--branch",
                entry["version"],
                _authed(entry["repository"]),
                str(dest),
            )
        head = _git("rev-parse", "HEAD", cwd=dest).strip()
        if head != entry["commit"]:
            raise LockError(f"{name}: {entry['version']} is {head}, lock says {entry['commit']}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] in {"-h", "--help"}:
        print(__doc__)
        return 0 if len(argv) > 1 else 2
    command, lock_path = argv[1], Path(argv[2])
    try:
        if command == "check":
            return cmd_check(lock_path, "--remote" in argv[3:])
        lock = load(lock_path)
        if command == "apps":
            print("\n".join(apps(lock)))
        elif command == "core":
            print(next((n for n, e in lock.items() if e.get("kind") == "core"), ""))
        elif command == "frappe-env":
            frappe = lock["frappe"]
            print(f"FRAPPE_REPOSITORY={shlex.quote(frappe['repository'])}")
            print(f"FRAPPE_VERSION={shlex.quote(frappe['version'])}")
        elif command == "apps-json":
            print(
                json.dumps(
                    [
                        {"url": lock[n]["repository"], "branch": lock[n]["version"]}
                        for n in apps(lock)
                    ],
                    indent=2,
                )
            )
        elif command == "verify-bench":
            return cmd_verify_bench(lock_path, Path(argv[3]))
        elif command == "checkout":
            return cmd_checkout(lock_path, Path(argv[3]))
        else:
            print(f"unknown command: {command}", file=sys.stderr)
            return 2
    except (LockError, KeyError, IndexError) as exc:
        print(f"lock.py {command}: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
