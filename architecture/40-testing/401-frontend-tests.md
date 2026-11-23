# 401 · Frontend tests

## Unit tests by folder

- `utils/`, `directives/`, `composables/`: input/output, edge cases, cleanup on unmount. No network.
- `stores/`: state transitions and derived values with the API layer faked.
- `api/` modules: correct request and response mapping with the client faked; error-code mapping.
- `shared/frappe/`: CSRF and trace headers, error envelope parsing, unknown-code fallback,
  expired-session handling, build-id mismatch, resource loading and error states.
- Components, views, layouts: rendering by props and slots, emitted events, keyboard and focus
  (especially overlays), state classes, axe scan.
- `sdk/permissions`: every helper case.

## Integration tests (`tests/integration/`)

- `login-wall`: guest → login with destination remembered; return after login; external redirect
  refused; logged-in user on login → launcher.
- `role-guard`: missing role or party type blocks the app route; present allows it.
- `registry`: launcher shows the intersection of build registry and server list (installed but not
  built; built but not permitted).
- `errors`: envelope → translated message, field errors on forms, fallback chain.

## Infrastructure

`tests/setup.ts`; `tests/mocks/` (MSW `handlers/` per feature area, `fixtures/`, `server.ts`);
`tests/utils/` (`render.ts` installing providers, `fake-session.ts`, `fake-router.ts`).
Feature apps reuse these through the same alias as the sdk.

## Rules

- `TST-FE-001` Vitest scans core and every app's frontend folder.
- `TST-FE-002` Network access in unit and integration tests MUST go through MSW; unhandled requests
  fail the test.
