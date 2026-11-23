# 33 · App registration: backend hook and frontend manifest

## Purpose

How a feature app appears in the launcher. Two declarations with one meaning: the backend hook
says **who may see it**, the frontend manifest says **what it renders**.

## Backend: `portal_apps` hook

Declared in the app's `hooks.py`, validated by the sdk schema:

| Field | Meaning |
|---|---|
| `id` | Unique app id, equal to the manifest id |
| `title` | Translation key of the display title |
| `icon` | Material Symbols name present in the icon union |
| `route` | Base portal route (under the portal path, never `/app`) |
| `roles` | Roles allowed to see the app |
| `party_types` | Optional: Party Type codes; external users must be member of a party with one of them |
| `requires_capabilities` | Optional: capabilities that must be active |

Core's app-list method reads all installed apps' entries, filters them by the current user's
roles, party types and active capabilities, and returns the result.

## Frontend: `manifest.ts`

Declared with the sdk `defineApp` helper: id, title key, icon, base path, navigation, routes
(aggregated from features) with role metadata, optional locale and style entries, and
`record_routes` (doctype → portal route pattern used to open search results and links, e.g.
`Leave Request` → `/hr/leave-requests/:name`).

## Rules

- `CT-REG-001` The app-list method MUST require a session.
- `CT-REG-002` The launcher MUST show the **intersection** of apps in the frontend build registry
  and apps returned by the server (covers installed-but-not-built and built-but-not-permitted).
- `CT-REG-003` The hook `id` and the manifest `id` MUST be equal; a contract test checks every
  app.
- `CT-REG-004` Being listed does not grant access: every API MUST still check roles, permissions
  and party scoping.
- `CT-REG-005` Every searchable doctype owned by an app with a portal view MUST have an entry in
  that app's `record_routes`; the route MUST exist in the manifest's routes. Core exposes the merged
  map to the backend (for search results) through the build registry.
