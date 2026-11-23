# 34 · Realtime events

## Purpose

Naming, scoping and payload rules for socket.io events between backend and portal.

## Rules

- `CT-RT-001` Events MUST be published only through the sdk helper
  `publish(app, feature, event, payload, *, user=None, doctype=None, docname=None)`.
- `CT-RT-002` Event names MUST be `<app>:<feature>:<event>` (kebab-case segments allowed for
  readability, e.g. `hr:leave-requests:updated`).
- `CT-RT-003` Every event MUST be scoped to a user or to a document room. Broadcasting to all
  connected users is forbidden.
- `CT-RT-004` Payloads MUST be pydantic models, MUST include `trace_id` when triggered by a
  request or job, and MUST NOT include data the recipient could not read through the API.
  Prefer sending identifiers and letting the client refetch.
- `CT-RT-005` The portal subscribes only through `shared/frappe/realtime.ts`; subscriptions are
  cleaned up on unmount.
