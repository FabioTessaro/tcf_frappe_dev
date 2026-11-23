# 400 · Testing strategy

## Layers

| Layer | Proves | Tools (decided) | Location |
|---|---|---|---|
| Static checks | Types, boundaries, styles, security patterns | vue-tsc, ESLint, Stylelint, Prettier, Ruff, mypy, import-linter | Config at repo roots |
| Unit | One unit in isolation | Vitest + Vue Test Utils; Frappe test runner (`bench run-tests`) | Next to the unit / slice `tests/` |
| Integration (frontend) | Router + guards + session, registry, views with stores and mocked backend | Vitest + MSW | `<core-app>/frontend/tests/integration/` |
| Contract | Agreements between core, apps, frontend and backend | Vitest; Python tests; scripts | `tests/contract/` (frontend), `<core-app>/tests/contract/` (backend), `platform` repo |
| Backend | Permissions, party scoping, guest rejection, validation, business rules | Frappe test runner | Slice `tests/` |
| End-to-end | Real journeys on a real site | Playwright | `<core-app>/frontend/tests/e2e/`, `<feature-app>/frontend/tests/e2e/` |
| Accessibility | WCAG 2.1 AA on components and journeys | axe-core (in Vitest and Playwright) | With component and e2e tests |
| Visual (optional) | Shared components render consistently | Storybook stories + visual comparison | Next to shared components |

## Rules

- `TST-STR-001` Every layer above except *Visual* is mandatory in CI.
- `TST-STR-002` Tests reference the rule IDs they verify in their name or docstring when they
  verify a guide rule (e.g. `test_guest_rejected__BE_API_001`).
- `TST-STR-003` Coverage thresholds (line coverage, enforced in CI):

  | Area | Minimum |
  |---|---|
  | Frontend `utils`, `shared/frappe`, `sdk`, router guards, stores | 90 % |
  | Backend `service.py`, `permissions.py`, core sdk | 90 % |
  | Frontend components and views; backend `queries.py` | 70 % |

- `TST-STR-004` Coverage is not sufficient: **every guest-reachable and every role- or
  party-restricted endpoint MUST have a backend test**, and every critical journey listed in
  [404-e2e](404-e2e.md) MUST exist as an e2e spec.
- `TST-STR-005` Texts are asserted through translation keys or error codes, not literal strings.
