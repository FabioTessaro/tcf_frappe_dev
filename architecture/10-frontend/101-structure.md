# 101 · Frontend structure

## Purpose

Folder layout, the feature slice and the component folder, with responsibilities.

## Dependency direction

`app → platform / features → shared`. Feature apps import only from core's `sdk` and `shared`.

## Core frontend tree

```
<core-app>/frontend/
├── public/                     favicon.svg, favicon.ico, apple-touch-icon.png (from brand logo)
├── plugins/                    discover-apps.ts, emit-shared-assets.ts, copy-index-html.ts
├── src/
│   ├── app/                    shell: App.vue, App.scss, main.ts, router/, providers/, layouts/
│   ├── platform/               core's own features: auth/ (public), launcher/
│   ├── sdk/                    contract for feature apps
│   ├── shared/                 components/, frappe/, composables/, stores/, directives/,
│   │                           utils/, constants/, types/, i18n/
│   ├── styles/                 global styles (core only)
│   ├── assets/                 fonts/, icons/, brand/, images/
│   ├── registry.d.ts, icon-names.d.ts (generated), env.d.ts
├── tests/                      setup.ts, mocks/, utils/, integration/, contract/, e2e/
├── vite.config.ts  vitest.config.ts  playwright.config.ts
├── tailwind.preset.ts  tailwind.config.ts  tsconfig.json
├── eslint.config.js  stylelint.config.js  .prettierrc
└── package.json
```

## Feature app frontend tree

```
<feature-app>/frontend/
├── manifest.ts, manifest.test.ts
├── icons.json
├── features/<feature>/          one slice per feature (below)
├── shared/                      parts reused by ≥ 2 features of this app only
├── styles/                      optional app-scoped styles: app.scss, _theme.scss
├── locales/                     app-wide strings: en.json, it.json, ...
└── tests/e2e/specs/
```

## The feature slice

| Folder / file | Holds | Responsibility |
|---|---|---|
| `api/` | `<feature>.api.ts`, `<feature>.api.types.ts` (generated section), `<feature>.api.test.ts`, optional `<feature>.mappers.ts` | The only place talking to the backend for this feature. Typed functions returning plain data. No UI, no state |
| `components/` | One component folder each, optional `index.ts` | Components used only by this feature |
| `composables/` | `use<Thing>.ts` + test | Feature logic combining API, state and reactivity |
| `stores/` | `<thing>.store.ts` + test | State outliving a view or shared by views of the feature |
| `types/` | `<thing>.types.ts`, `index.ts` | Feature-specific types |
| `views/` | `<Name>View/` folders | Routed pages; compose components and composables; little logic |
| `locales/` | `en.json`, `it.json`, ... | Feature strings, namespaced by app and feature |
| `routes.ts` | — | Feature routes with roles, titles, public marks. The only way a feature becomes reachable |
| `index.ts` | — | Public surface of the feature |

## The component folder

Applies to components, views and layouts: `<Name>.vue`, `<Name>.scss`, `<Name>.types.ts`
(omitted when trivial), `<Name>.test.ts`, `<Name>.stories.ts` (optional), `index.ts`.

## Rules

- `FE-STR-001` Feature apps MUST NOT import from other feature apps; features MUST NOT import from
  other features; code outside a feature MUST import only through its `index.ts`.
- `FE-STR-002` Every feature MUST follow the slice layout above; core's `platform/` features too.
- `FE-STR-003` Components, views and layouts MUST be folders following the component pattern.
- `FE-STR-004` `shared/` MUST NOT know any feature or business entity. Parts used by one app only
  live in that app's `shared/`; they are promoted to core only when another app needs them.
- `FE-STR-005` Unit tests sit next to the unit; cross-cutting tests live in `tests/`.
- `FE-STR-006` Re-export files exist only at feature, component-folder and category boundaries.
- `FE-STR-007` Naming: PascalCase components and views, `use` prefix for composables, `.store`,
  `.api`, `.types`, `.test` suffixes, `_` prefix for Sass partials.
- `FE-STR-008` The `api/` module is the only code calling `shared/frappe`; it MUST use the
  generated types for request and response shapes.

## Shared layer contents

- `components/` grouped by role, allowed direction primitives → forms, overlays, data, feedback →
  layout, navigation; each category has an `index.ts`:
  - `primitives/` (Button, Input, Select, Checkbox, **Icon** — the only way to render icons —,
    **Logo** — brand symbols)
  - `forms/`, `overlays/` (own focus, stacking, dismissal), `data/`, `feedback/` (incl.
    `ConnectionBanner`), `navigation/`, `layout/`.
- `frappe/` ([104-frappe-client](104-frappe-client.md)).
- `composables/`, `stores/` (theme, sidebar), `directives/`, `utils/` (pure functions),
  `constants/` (storage keys, limits, generated roles), `types/`, `i18n/` ([108-i18n](108-i18n.md)).

## Verification

ESLint boundary rules (`eslint-plugin-boundaries`) enforce FE-STR-001, 004, 006; directory
structure contract test enforces FE-STR-002, 003.
