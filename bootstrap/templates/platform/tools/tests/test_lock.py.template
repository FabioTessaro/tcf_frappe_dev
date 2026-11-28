"""Tests of tools/lock.py and tools/contracts.py (`just test-unit`)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import contracts  # noqa: E402
import lock  # noqa: E402

SHA = "a" * 40


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class LockTests(unittest.TestCase):
    def test_valid_lock_has_no_problems(self) -> None:
        data = {"frappe": {"repository": "https://x/frappe", "version": "v16.0.0", "commit": SHA}}
        self.assertEqual(lock.problems(data), [])

    def test_missing_frappe_bad_commit_and_kind(self) -> None:
        data = {"hr": {"repository": "git@github.com:o/hr.git", "version": "v1", "commit": "x"}}
        found = "\n".join(lock.problems(data))
        for text in ("[frappe] is missing", "40-character", "kind must be", "https://"):
            self.assertIn(text, found)

    def test_lock_keys_must_be_in_renovate_order(self) -> None:
        entry = {"repository": "https://x", "kind": "feature", "version": "v1.0.0", "commit": SHA}
        frappe = {"repository": "https://x", "version": "v16.0.0", "commit": SHA}
        found = "\n".join(lock.problems({"frappe": frappe, "hr": entry}))
        self.assertIn("consecutive", found)
        ordered = {"kind": "feature", **frappe}
        self.assertEqual(lock.problems({"frappe": frappe, "hr": ordered}), [])

    def test_apps_and_core(self) -> None:
        entry = {"repository": "https://x", "version": "v1.0.0", "commit": SHA}
        data = {
            "frappe": entry,
            "base": {**entry, "kind": "core"},
            "hr": {**entry, "kind": "feature"},
        }
        self.assertEqual(lock.apps(data), ["base", "hr"])


class ContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        entry = {"repository": "https://x", "commit": SHA}
        self.lock = {
            "frappe": {**entry, "version": "v16.0.0"},
            "base": {**entry, "version": "v0.1.0", "kind": "core"},
            "hr": {**entry, "version": "v0.1.0", "kind": "feature"},
        }
        write(
            self.root / "base/base/hooks.py",
            'required_apps: list[str] = []
core_sdk_version = "0.1.0"
',
        )
        write(
            self.root / "hr/hr/hooks.py",
            'required_apps = ["base"]\ncore_sdk_version = ">=0.1,<0.2"\n'
            'portal_apps = [{"id": "hr"}]\n',
        )
        write(self.root / "hr/frontend/manifest.ts", 'export default defineApp({ id: "hr" });\n')

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_conforming_apps_pass(self) -> None:
        self.assertEqual(contracts.check(self.root, self.lock), [])

    def test_sdk_range_and_core_dependency(self) -> None:
        write(self.root / "hr/hr/hooks.py", 'required_apps = []\ncore_sdk_version = ">=1.0,<2"\n')
        found = "\n".join(contracts.check(self.root, self.lock))
        self.assertIn("SYS-DEP-001", found)
        self.assertIn("SYS-DEP-002", found)

    def test_cycle_and_manifest_id(self) -> None:
        write(self.root / "base/base/hooks.py", 'required_apps = ["hr"]\n')
        write(self.root / "hr/frontend/manifest.ts", 'export default defineApp({ id: "other" });\n')
        found = "\n".join(contracts.check(self.root, self.lock))
        self.assertIn("SYS-DEP-003", found)
        self.assertIn("CT-REG-003", found)

    def test_link_to_app_outside_required_apps(self) -> None:
        self.lock["qms"] = {**self.lock["hr"]}
        write(
            self.root / "qms/qms/hooks.py",
            'required_apps = ["base"]\ncore_sdk_version = ">=0.1,<0.2"\n',
        )
        write(
            self.root / "qms/qms/audits/doctype/audit/audit.json",
            json.dumps({"doctype": "DocType", "name": "Audit", "fields": []}),
        )
        write(
            self.root / "hr/hr/leave/doctype/leave/leave.json",
            json.dumps(
                {
                    "doctype": "DocType",
                    "name": "Leave",
                    "fields": [{"fieldname": "audit", "fieldtype": "Link", "options": "Audit"}],
                }
            ),
        )
        self.assertIn("SYS-DEP-006", "\n".join(contracts.check(self.root, self.lock)))


if __name__ == "__main__":
    unittest.main()
