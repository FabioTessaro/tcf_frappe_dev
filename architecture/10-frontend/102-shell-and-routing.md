# 102 · Shell, routing and layouts

## Purpose

The application shell in `src/app/` and core's own features in `src/platform/`.

## Shell (`src/app/`): wiring only, no business logic

- `App.vue` / `App.scss`: root component; renders the layout chosen by the route; hosts global
  overlays (toasts, update prompt).
- `main.ts`: creates the app, installs providers in order, loads the initial session, mounts.
- `router/index.ts`: router with the portal base path, guards, dynamic app routes.
- `router/guards.ts` (+ test): login wall and role/party-type checks (UX only).
- `router/routes.ts`: assembles core routes (public auth routes, protected launcher, catch-all).
- `router/register-apps.ts` (+ test): builds each app's route subtree from the registry with lazy
  views, the app shell layout and declared role metadata.
- `providers/`: `pinia.ts`, `i18n.ts`, `error-handler.ts`, `app-registry.ts`, `index.ts`.
- `layouts/`: `AuthLayout` (public), `LauncherLayout`, `AppShellLayout` (navbar and sidebar from
  the active app's navigation). Layouts fetch no data.

## Platform features (`src/platform/`)

- `auth/`: login, logout, password reset request, current session. Its routes are public.
- `launcher/`: lists the apps the user may open ([03-contracts/33-registry-manifests](../03-contracts/33-registry-manifests.md)).

## Rules

- `FE-SHELL-001` Every route MUST be protected unless explicitly marked public; only auth routes
  carry the public mark.
- `FE-SHELL-002` Guards MUST redirect guests to login remembering the destination, redirect
  logged-in users away from auth pages, and block app routes when roles or party types are missing.
  Guards are UX, not security.
- `FE-SHELL-003` The remembered destination MUST be validated as an internal portal path.
- `FE-SHELL-004` The error handler MUST report errors with `trace_id`, show a user-facing fallback,
  and reload the page **once** on a failed lazy chunk load.
- `FE-SHELL-005` Unknown routes: guests → login; logged-in users → 404 view.
