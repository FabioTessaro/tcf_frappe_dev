# 100 · Frontend composition

## Purpose

How the single portal application is assembled from the core app and every feature app.

Stack: Vue 3, TypeScript, Tailwind CSS, Sass, Pinia, Vue Router, Vite; self-hosted Google Fonts
and Material Symbols.

## Options considered

| Option | How it works | Pros | Cons |
|---|---|---|---|
| **1. Build-time composition** (chosen) | Core's build discovers each installed app's frontend source and bundles it as lazy chunks | One Vue instance, one router, one design system, type-safe imports | Core must rebuild when any app's frontend changes; a broken app can break the build |
| 2. Runtime composition (Module Federation) | Each app builds a remote; core loads remotes from the registry | Independent deploys | Shared singletons, version skew, weaker typing, complexity |
| 3. Separate SPAs | Core is only login and launcher; each app is its own SPA | Strongest isolation | No seamless shell; duplicated runtimes |

## Rules

- `FE-COMP-001` The portal MUST use build-time composition (option 1). Moving to option 2 requires
  a guide change; manifests and registry are designed to be independent of the loading mechanism.
- `FE-COMP-002` A **discovery plugin** (`discover-apps.ts`) MUST read the installed apps, find each
  app's `frontend/manifest.ts`, and produce a virtual registry module of lazy imports; it also
  collects each app's locale files and app-scoped style entry, and skips apps without a frontend.
- `FE-COMP-003` A **route registrar** MUST turn each manifest into a lazy route subtree under the
  app's base path. Users download only the chunks of the apps they open.
- `FE-COMP-004` Feature apps reach core only through the aliases to `sdk` and `shared`, configured
  in both the Vite and TypeScript configuration.
- `FE-COMP-005` Tailwind content scanning MUST include every app's frontend folder; feature apps
  extend core's Tailwind preset so palette and fonts stay central.
- `FE-COMP-006` Feature apps MUST NOT contain build tooling or a `package.json`; core builds,
  lints and tests them.
- `FE-COMP-007` Every app and feature route MUST be lazy-loaded.

## Frappe wiring

- `FE-COMP-010` The build outputs into `<core-app>/public/frontend/`; `copy-index-html.ts` places
  the entry HTML in `<core-app>/www/portal.html`. A route rule sends every portal path to that
  page; the router uses history mode with the portal path as base.
- `FE-COMP-011` In development the Vite dev server (port 5173) runs separately with hot reload and
  proxies API, assets, files and socket.io to the bench.
- `FE-COMP-012` The portal is same-origin: the Frappe session cookie authenticates; the page
  controller injects the CSRF token and boot data ([03-contracts/32-boot-data](../03-contracts/32-boot-data.md)).
