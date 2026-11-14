# Multi-App Vue 3 Frontend on Frappe: Architecture Reference

Stack: Vue 3, TypeScript, Tailwind CSS, Sass, self-hosted Google Fonts, self-hosted Google Material icons, Pinia, Vue Router, on a single Frappe site.

This document describes **structure and division of responsibilities only**. It contains no implementation code.

---

## 1. Goal and scope

One Frappe site hosts several Frappe apps of three kinds:

| Kind | Example | Role |
|---|---|---|
| **Core app** | `core` | Owns the Vue shell, login pages, app launcher, shared components, global theming and typography |
| **Feature apps** | `hr`, others | Add their own features and views (leave requests, expense claims, ...) and register themselves in core's launcher |
| **Public website app** | `site` | Serves the public HTML + SCSS + JS website, shows public data (job postings, news) and links visitors to the portal |

The portal (everything under the portal path) is a single Vue application delivered by core. The public website is an ordinary Frappe website app and is not part of the Vue build.

---

## 2. Core principles

1. **Dependency direction is one-way:** `app -> platform/features -> shared`. Feature apps import only from core's `sdk` and `shared`. Feature apps never import from each other. Core never imports from feature apps except through the generated registry.
2. **Vertical slices:** each feature owns its API calls, components, composables, state, types, views, routes, translations and tests. Deleting a feature means deleting one folder.
3. **Colocation:** things that change together live together. A component's template, styles, types, tests and stories sit in one folder. A feature's translations sit inside the feature.
4. **Shared means used by two or more consumers and knowing nothing about any feature.** Parts used only inside one app live in that app's own shared folder.
5. **Frontend role checks are UX only.** Real enforcement happens in whitelisted Python methods and doctype permissions.
6. **Only the login flow is public inside the portal.** Everything else, including the app launcher, requires an open session. Routes are protected by default and must be explicitly marked public.
7. **Tokens over hardcoded values.** Components never hardcode colors, font sizes or spacing. Every value comes from a design token.
8. **Small, versioned contract.** Besides shared components, the only thing feature apps depend on in core is the `sdk`.
9. **Nothing loads from third parties at runtime.** Fonts and icons are downloaded from Google once and self-hosted, so they never depend on an external host and are served with long cache lifetimes from your own server.

---

## 3. Access model (the login wall)

| Area | Access |
|---|---|
| Public website (home and its pages) | Public |
| Portal login and forgot-password pages | Public, guests only. A logged-in user opening them is redirected to the launcher |
| **App launcher** (portal root) | **Session required** |
| Feature app pages (portal, per app) | Session required **and** a role allowed by that app's manifest or route |
| Unknown portal routes | Guests are redirected to login; logged-in users see a 404 page |
| Frappe Desk | Untouched, owned by Frappe |

Protection is enforced in three independent layers:

1. **Server entry point.** The portal's page controller redirects guests requesting any non-login portal path to the login page, remembering where they wanted to go. Boot data given to guests contains nothing user-specific.
2. **Router guard.** Every route is protected unless explicitly marked public; only the auth routes carry that mark. After login the user returns to the remembered destination, which must be validated as an internal portal path.
3. **API layer.** The launcher's app-list method and every feature app method are whitelisted without guest access, so Frappe rejects calls without a session even if the UI is bypassed. Role and permission checks happen here too.

The built bundle is a static asset and is not secret. Data protection therefore lives in the API layer, and nothing sensitive may be placed in the bundle or in guest boot data.

---

## 4. Backend registry

Each feature app declares itself to core through a **custom hook** in its own hooks file. The declaration carries: a unique app id, a display title, an icon name (from the Material icon set in use), the portal route, and the list of roles allowed to see it.

Core exposes one authenticated method that:

1. reads the declarations of all installed apps,
2. filters them by the current user's roles,
3. returns the result to the launcher.

Installing or uninstalling an app updates the list automatically. The method requires a session. Every API of every app must still check roles and permissions on its own.

---

## 5. Frontend composition options

| Option | How it works | Pros | Cons |
|---|---|---|---|
| **1. Build-time composition** (recommended start) | Core's build discovers each installed app's frontend source and bundles it as lazy-loaded chunks | One Vue instance, one router, one design system, type-safe imports | Core must rebuild when any app's frontend changes; a broken app can break the build |
| **2. Runtime composition (Module Federation)** | Each app builds its own remote bundle; core loads the remotes it learns about from the registry | Independent deploys | Shared singletons, version skew, weaker typing, real complexity |
| **3. Separate SPAs** | Core is only login and launcher; every app is its own SPA importing core code through an alias | Most robust isolation | No seamless shell; duplicated runtimes |

The rest of this document assumes option 1. Because the manifest and registry design is independent of the loading mechanism, moving to option 2 later does not require rewriting feature apps.

---

## 6. How build-time composition works

- A **discovery plugin** in core's build reads the list of installed apps, looks for a manifest file in each app's frontend folder, and produces a virtual registry module of lazy imports. It also collects each app's translation files and app-scoped style entry.
- A **route registrar** in core's router turns every manifest into routes under that app's portal path. Users download only the chunk of the app they open.
- **Aliases** in the build and type configuration let feature apps reach core's `sdk` and `shared`.
- **Tailwind content scanning** includes every app's frontend folder, otherwise their classes are purged. Feature apps extend core's Tailwind preset so palette and fonts stay centralized.
- **Test discovery** works the same way: core's test runners also scan every app's frontend folder (see section 14).
- The **launcher** shows the intersection of what is registered in the build and what the server returns for the user. This covers an app installed on the site but not yet rebuilt, and the reverse.
- Do not use `/app` as a prefix: Frappe Desk owns it.

---

## 7. Frappe wiring and caching notes

- **Serving the SPA.** The build outputs into core's public assets folder; a post-build step copies the entry HTML into core's `www` folder as the portal page. A route rule sends every portal path to that page. The router runs in history mode with the portal path as its base.
- **Development.** Frappe's bench runs the backend; the Vite dev server runs separately with hot reload and proxies API, assets, files and socket.io calls to the bench.
- **Auth.** The SPA is same-origin, so the Frappe session cookie works. The portal page controller injects the CSRF token and boot data, and the request client sends the token with every call.
- **Backend calls.** Feature API modules call whitelisted methods or the resource API. Python modules mirror frontend features one to one.
- **No service worker.** The portal is a plain web app and relies on normal browser caching. Built files carry content hashes in their names and are cached for a long time; the entry page is never cached for long, so every deploy is picked up on the next page load.
- **Stale tabs after a deploy.** A tab left open across a deploy may request a lazy chunk that no longer exists. The global error handler treats a failed chunk load by reloading the page once.
- **Offline is not supported.** Opening the portal offline shows the browser's own error page. Losing the connection mid-session shows an in-app "connection lost" banner.

---

## 8. Folder structure (overview)

Files shown are representative: each folder lists the files it normally holds. Section 9 explains each one. A folder named after a thing (for example `Button/`) shows the pattern that repeats for every sibling.

```
apps/core/
├── frontend/
│   ├── public/
│   │   ├── favicon.svg
│   │   ├── favicon.ico
│   │   └── apple-touch-icon.png
│   ├── plugins/
│   │   ├── discover-apps.ts
│   │   ├── emit-shared-assets.ts
│   │   └── copy-index-html.ts
│   ├── src/
│   │   ├── app/
│   │   │   ├── App.vue
│   │   │   ├── App.scss
│   │   │   ├── main.ts
│   │   │   ├── router/
│   │   │   │   ├── index.ts
│   │   │   │   ├── guards.ts
│   │   │   │   ├── guards.test.ts
│   │   │   │   ├── routes.ts
│   │   │   │   ├── register-apps.ts
│   │   │   │   └── register-apps.test.ts
│   │   │   ├── providers/
│   │   │   │   ├── index.ts
│   │   │   │   ├── pinia.ts
│   │   │   │   ├── i18n.ts
│   │   │   │   ├── error-handler.ts
│   │   │   │   └── app-registry.ts
│   │   │   └── layouts/
│   │   │       ├── AuthLayout/
│   │   │       │   ├── AuthLayout.vue
│   │   │       │   ├── AuthLayout.scss
│   │   │       │   ├── AuthLayout.test.ts
│   │   │       │   └── index.ts
│   │   │       ├── LauncherLayout/        (same four files)
│   │   │       └── AppShellLayout/        (same four files)
│   │   │
│   │   ├── platform/
│   │   │   ├── auth/
│   │   │   │   ├── api/
│   │   │   │   │   ├── auth.api.ts
│   │   │   │   │   ├── auth.api.types.ts
│   │   │   │   │   └── auth.api.test.ts
│   │   │   │   ├── components/
│   │   │   │   │   ├── LoginForm/
│   │   │   │   │   │   ├── LoginForm.vue
│   │   │   │   │   │   ├── LoginForm.scss
│   │   │   │   │   │   ├── LoginForm.types.ts
│   │   │   │   │   │   ├── LoginForm.test.ts
│   │   │   │   │   │   └── index.ts
│   │   │   │   │   └── ForgotPasswordForm/   (same five files)
│   │   │   │   ├── composables/
│   │   │   │   │   ├── useAuth.ts
│   │   │   │   │   └── useAuth.test.ts
│   │   │   │   ├── stores/
│   │   │   │   │   ├── session.store.ts
│   │   │   │   │   └── session.store.test.ts
│   │   │   │   ├── types/
│   │   │   │   │   ├── session.types.ts
│   │   │   │   │   └── index.ts
│   │   │   │   ├── views/
│   │   │   │   │   ├── LoginView/
│   │   │   │   │   │   ├── LoginView.vue
│   │   │   │   │   │   ├── LoginView.scss
│   │   │   │   │   │   ├── LoginView.test.ts
│   │   │   │   │   │   └── index.ts
│   │   │   │   │   └── ForgotPasswordView/   (same four files)
│   │   │   │   ├── locales/
│   │   │   │   │   ├── en.json
│   │   │   │   │   └── it.json
│   │   │   │   ├── routes.ts
│   │   │   │   └── index.ts
│   │   │   └── launcher/
│   │   │       ├── api/                    (apps.api.ts, apps.api.types.ts, apps.api.test.ts)
│   │   │       ├── components/             (AppCard/, AppGrid/ with the five-file pattern)
│   │   │       ├── composables/            (useAvailableApps.ts + test)
│   │   │       ├── stores/                 (apps.store.ts + test)
│   │   │       ├── types/                  (apps.types.ts, index.ts)
│   │   │       ├── views/                  (LauncherView/ with the four-file pattern)
│   │   │       ├── locales/                (en.json, it.json)
│   │   │       ├── routes.ts
│   │   │       └── index.ts
│   │   │
│   │   ├── sdk/
│   │   │   ├── define-app.ts
│   │   │   ├── manifest.types.ts
│   │   │   ├── nav.types.ts
│   │   │   ├── route-meta.types.ts
│   │   │   ├── permissions.ts
│   │   │   ├── permissions.test.ts
│   │   │   └── index.ts
│   │   │
│   │   ├── shared/
│   │   │   ├── components/
│   │   │   │   ├── primitives/
│   │   │   │   │   ├── Button/
│   │   │   │   │   │   ├── Button.vue
│   │   │   │   │   │   ├── Button.scss
│   │   │   │   │   │   ├── Button.types.ts
│   │   │   │   │   │   ├── Button.test.ts
│   │   │   │   │   │   ├── Button.stories.ts   (optional)
│   │   │   │   │   │   └── index.ts
│   │   │   │   │   ├── Icon/                (same pattern, plus icons.json: core's own icon list)
│   │   │   │   │   ├── Logo/                (same pattern, renders brand symbols)
│   │   │   │   │   ├── Input/               (same pattern)
│   │   │   │   │   └── index.ts             (category re-export)
│   │   │   │   ├── forms/                  (FormField/, FormGroup/, ... + index.ts)
│   │   │   │   ├── overlays/               (Modal/, Drawer/, Popover/, Tooltip/, Dropdown/ + index.ts)
│   │   │   │   ├── data/                   (Table/, List/, Pagination/, Badge/, Avatar/ + index.ts)
│   │   │   │   ├── feedback/               (Toast/, Skeleton/, Spinner/, EmptyState/, ConnectionBanner/ + index.ts)
│   │   │   │   ├── navigation/             (Tabs/, Breadcrumbs/, Sidebar/, Navbar/ + index.ts)
│   │   │   │   └── layout/                 (PageContainer/, Stack/, Grid/, Card/ + index.ts)
│   │   │   ├── frappe/
│   │   │   │   ├── client.ts
│   │   │   │   ├── client.test.ts
│   │   │   │   ├── call.ts
│   │   │   │   ├── resource.ts
│   │   │   │   ├── resource.test.ts
│   │   │   │   ├── session.ts
│   │   │   │   ├── realtime.ts
│   │   │   │   ├── permissions.ts
│   │   │   │   ├── types.ts
│   │   │   │   └── index.ts
│   │   │   ├── composables/                (useDebounce.ts, useBreakpoint.ts, useOnlineStatus.ts + tests + index.ts)
│   │   │   ├── stores/                     (ui.store.ts, ui.store.test.ts)
│   │   │   ├── directives/                 (click-outside.ts, focus.ts + tests + index.ts)
│   │   │   ├── utils/                      (format.ts, date.ts, string.ts, validators.ts + tests + index.ts)
│   │   │   ├── constants/                  (storage-keys.ts, limits.ts, roles.ts, index.ts)
│   │   │   ├── types/                      (common.types.ts, index.ts)
│   │   │   └── i18n/
│   │   │       ├── index.ts
│   │   │       ├── merge-locales.ts
│   │   │       ├── merge-locales.test.ts
│   │   │       ├── languages.ts
│   │   │       ├── languages.test.ts
│   │   │       ├── apply-language.ts
│   │   │       ├── apply-language.test.ts
│   │   │       └── locales/
│   │   │           ├── en.json
│   │   │           └── it.json
│   │   │
│   │   ├── styles/                         (global, core only)
│   │   │   ├── main.scss
│   │   │   ├── tailwind.css
│   │   │   ├── abstracts/
│   │   │   │   ├── _variables.scss
│   │   │   │   ├── _mixins.scss
│   │   │   │   ├── _functions.scss
│   │   │   │   └── _index.scss
│   │   │   ├── base/
│   │   │   │   ├── _reset.scss
│   │   │   │   └── _elements.scss
│   │   │   ├── typography/
│   │   │   │   ├── _index.scss
│   │   │   │   ├── _resolve.scss
│   │   │   │   ├── _roles.scss
│   │   │   │   ├── typefaces/
│   │   │   │   │   ├── _index.scss
│   │   │   │   │   └── _noto-sans.scss     (one file per typeface)
│   │   │   │   ├── scripts/
│   │   │   │   │   ├── _index.scss
│   │   │   │   │   ├── _latin.scss
│   │   │   │   │   ├── _japanese.scss
│   │   │   │   │   ├── _chinese-simplified.scss
│   │   │   │   │   └── _chinese-traditional.scss
│   │   │   │   └── devices/
│   │   │   │       ├── _index.scss
│   │   │   │       ├── _desktop.scss
│   │   │   │       └── _mobile.scss
│   │   │   ├── themes/
│   │   │   │   ├── _tokens.scss
│   │   │   │   ├── _app-themable.scss
│   │   │   │   ├── _light.scss
│   │   │   │   └── _dark.scss
│   │   │   └── vendor/
│   │   │       └── _third-party-overrides.scss
│   │   │
│   │   ├── assets/
│   │   │   ├── fonts/                      (downloaded from Google Fonts)
│   │   │   │   └── noto-sans/              (one folder per typeface)
│   │   │   │       ├── latin/              (variable font slices)
│   │   │   │       ├── japanese/
│   │   │   │       ├── chinese-simplified/
│   │   │   │       ├── chinese-traditional/
│   │   │   │       ├── LICENSE.txt
│   │   │   │       └── SOURCE.md
│   │   │   ├── icons/                      (downloaded from Google Material icons)
│   │   │   │   └── material-symbols/
│   │   │   │       ├── (the downloaded icon files in the chosen delivery format)
│   │   │   │       ├── LICENSE.txt
│   │   │   │       └── SOURCE.md
│   │   │   ├── brand/                      (logo, wordmark, symbols as vector files)
│   │   │   └── images/
│   │   ├── registry.d.ts
│   │   ├── icon-names.d.ts                 (generated from the merged icons.json lists)
│   │   └── env.d.ts
│   │
│   ├── tests/
│   │   ├── setup.ts
│   │   ├── mocks/
│   │   │   ├── handlers/                   (one file per feature area, e.g. auth.ts, apps.ts)
│   │   │   ├── fixtures/                   (sample users, roles, app lists, documents)
│   │   │   └── server.ts
│   │   ├── utils/
│   │   │   ├── render.ts
│   │   │   ├── fake-session.ts
│   │   │   └── fake-router.ts
│   │   ├── integration/
│   │   │   ├── login-wall.test.ts
│   │   │   ├── role-guard.test.ts
│   │   │   └── registry.test.ts
│   │   ├── contract/
│   │   │   ├── manifests.test.ts
│   │   │   ├── locales-parity.test.ts
│   │   │   ├── tokens.test.ts
│   │   │   ├── typography.test.ts
│   │   │   └── icons.test.ts
│   │   └── e2e/
│   │       ├── global-setup.ts
│   │       ├── fixtures/                   (logged-in users per role, seeded data)
│   │       ├── pages/                      (page objects: login, launcher, app shell)
│   │       └── specs/                      (login-wall.spec.ts, launcher.spec.ts, connection.spec.ts, ...)
│   ├── vite.config.ts
│   ├── vitest.config.ts
│   ├── playwright.config.ts
│   ├── tailwind.preset.ts
│   ├── tailwind.config.ts
│   ├── tsconfig.json
│   ├── eslint.config.js
│   ├── stylelint.config.js
│   └── package.json
├── core/
│   ├── __init__.py
│   ├── hooks.py
│   ├── modules.txt
│   ├── patches.txt
│   ├── config/
│   │   └── __init__.py
│   ├── api/
│   │   ├── __init__.py
│   │   ├── apps.py
│   │   └── session.py
│   ├── tests/
│   │   ├── __init__.py
│   │   ├── test_apps_api.py
│   │   ├── test_session_api.py
│   │   └── test_portal_page.py
│   ├── public/frontend/
│   ├── public/shared-assets/
│   └── www/
│       ├── portal.html
│       └── portal.py
└── package.json

apps/hr/                                  (any feature app follows this shape)
├── frontend/
│   ├── manifest.ts
│   ├── manifest.test.ts
│   ├── icons.json
│   ├── features/
│   │   ├── leave-requests/
│   │   │   ├── api/                      (leave-requests.api.ts, .types.ts, .test.ts)
│   │   │   ├── components/               (LeaveRequestForm/, LeaveBalanceCard/ with the five-file pattern)
│   │   │   ├── composables/              (useLeaveBalance.ts + test)
│   │   │   ├── stores/                   (leave-requests.store.ts + test)
│   │   │   ├── types/                    (leave-requests.types.ts, index.ts)
│   │   │   ├── views/                    (LeaveListView/, LeaveDetailView/ with the four-file pattern)
│   │   │   ├── locales/                  (en.json, it.json)
│   │   │   ├── routes.ts
│   │   │   └── index.ts
│   │   └── expense-claims/               (same slice layout)
│   ├── shared/
│   │   ├── components/                   (app-local, five-file pattern)
│   │   ├── composables/
│   │   └── types/
│   ├── styles/                           (optional, app-scoped only)
│   │   ├── app.scss
│   │   └── _theme.scss
│   ├── locales/                          (app-wide strings)
│   │   ├── en.json
│   │   └── it.json
│   └── tests/
│       └── e2e/
│           └── specs/                    (leave-request.spec.ts, expense-claim.spec.ts)
└── hr/
    ├── __init__.py
    ├── hooks.py
    ├── modules.txt
    ├── api/
    │   ├── __init__.py
    │   ├── leave_requests.py
    │   └── expense_claims.py
    ├── tests/
    │   ├── test_leave_requests_api.py
    │   └── test_expense_claims_api.py
    └── hr/doctype/

apps/site/                                (public website app; adapt to your existing site)
└── site/
    ├── __init__.py
    ├── hooks.py
    ├── icons.json
    ├── api/
    │   ├── __init__.py
    │   └── public.py
    ├── tests/
    │   └── test_public_api.py
    ├── public/
    │   ├── scss/
    │   ├── css/
    │   ├── js/
    │   ├── images/
    │   └── fonts/
    ├── templates/
    └── www/
        ├── index.html / index.py
        ├── jobs.html / jobs.py
        └── news.html / news.py
```

---

## 9. Responsibilities in detail

Each entry says what the folder or file is for, what it is responsible for, and where its responsibility ends.

### 9.1 `core/frontend/` root files

- **`vite.config.ts`**: the single build configuration for the whole portal. Responsible for path aliases to the `sdk` and `shared` layers, registering the custom plugins, the public base path, the output folder, and the dev-server proxy. Not responsible for runtime logic.
- **`vitest.config.ts`**: configuration of unit and integration tests. Responsible for the test environment, the global setup file, coverage settings, and scanning test files in core and in every feature app's frontend folder.
- **`playwright.config.ts`**: configuration of end-to-end tests. Responsible for the base URL of the test site, browser projects (desktop and mobile viewport), the global setup that prepares data and users, and discovering spec files in core and in every feature app.
- **`tailwind.preset.ts`**: the shared Tailwind vocabulary. Maps palette, spacing and radii to design tokens and exposes the typography roles as text utilities, so every class resolves to a token. Feature apps extend it.
- **`tailwind.config.ts`**: applies the preset and declares which files Tailwind scans (core and every app's frontend).
- **`tsconfig.json`**: strict type checking and the path aliases that give feature apps access to `sdk` and `shared`.
- **`eslint.config.js`**: architecture enforcement. Boundary rules (section 2), no app-to-app imports, no feature-to-feature imports, no direct imports into a feature bypassing its public file.
- **`stylelint.config.js`**: style rules for SCSS. Responsible for forbidding raw color and font values outside the token files, and forbidding direct font family, size, line-height or letter-spacing settings in components (they must use type roles), enforcing the abstracts import style, and keeping selectors scoped.
- **`package.json`**: frontend dependencies and scripts for development, build, test, lint and type check. Feature apps have no package file of their own.

### 9.2 `public/`

Static files copied into the build untouched.

- **`favicon.svg`, `favicon.ico`, `apple-touch-icon.png`**: browser tab and home-screen shortcut icons, generated from the brand logo. These are **not** the Material icons used inside the UI.
- **No offline page.** Without a service worker nothing could serve one, so offline users see the browser's own error page.

### 9.3 `plugins/`

Custom build-time plugins. They contain build logic, never runtime logic.

- **`discover-apps.ts`**: reads the list of installed apps, finds each app's manifest, and produces the virtual registry module. Also collects each app's translation files and app-scoped style entry. Skips apps without a frontend folder.
- **`emit-shared-assets.ts`**: merges the `icons.json` lists of core, every feature app and the website app into one union; produces the icon subset used by the portal, the generated icon-name types, and the static shared-assets bundle published for the website (section 9.13).
- **`copy-index-html.ts`**: after each production build, places the generated entry HTML where Frappe serves the portal page from, so the page controller can inject boot data.

### 9.4 `src/app/` (the shell)

Wiring only. No business logic.

- **`App.vue` and `App.scss`**: the root component and its styles. Renders the layout selected by the current route and hosts global overlays such as toasts and the update prompt.
- **`main.ts`**: application entry. Creates the Vue app, installs providers in order, loads the initial session, mounts.
- **`router/index.ts`**: creates the router, sets the base path, installs guards and dynamic app routes.
- **`router/guards.ts`** and **`guards.test.ts`**: implement and verify the login wall and role checks. Responsible for treating every route as protected unless marked public, redirecting guests to login while remembering the destination, redirecting logged-in users away from login pages, and blocking app routes when roles are missing. Not responsible for real security.
- **`router/routes.ts`**: assembles core routes (public auth routes, protected launcher, catch-all) from the platform features' own route files.
- **`router/register-apps.ts`** and its test: create, for each app in the registry, a route subtree with lazy views, the app shell layout and the declared role metadata.
- **`providers/`**: one small module per global capability, plus an index that installs them in order.
  - `pinia.ts`: state management setup.
  - `i18n.ts`: creates the translation instance from the merged locale files.
  - `error-handler.ts`: global error and unhandled-rejection handling, reporting, user-facing fallback, and a single page reload when a lazy chunk fails to load after a deploy.
  - `app-registry.ts`: exposes the generated registry to the app.
- **`layouts/`**: page frames. Each layout is a component folder (template, styles, test, re-export). No data fetching.
  - `AuthLayout`: public frame for login and forgot-password.
  - `LauncherLayout`: authenticated frame for the app selection page.
  - `AppShellLayout`: authenticated frame inside an app; renders the shared navbar and sidebar from the active app's declared navigation.

### 9.5 `src/platform/` (core's own features)

Core's features use the same slice shape as any feature app.

- **`auth/`** (the only public feature): login, logout, password reset requests, and the current session. Its routes are marked public.
- **`launcher/`** (requires a session): shows the apps the user may open and navigates into them. Its route is protected.

Both contain the full slice file set described in 9.6, including their own `locales/` folder.

### 9.6 The feature slice: files each folder should hold

Every feature, in core or in an app, is organised the same way. Test files sit next to the file they test.

| Folder or file | Files it normally holds | Responsibility |
|---|---|---|
| `api/` | `<feature>.api.ts`, `<feature>.api.types.ts`, `<feature>.api.test.ts`, optionally `<feature>.mappers.ts` | The only place that talks to the backend for this feature. Typed functions returning plain data. Mappers translate server shapes to UI shapes. No UI, no state. |
| `components/` | One folder per component (see 9.7) and an optional `index.ts` | Components used only by this feature. Presentational where possible. |
| `composables/` | `use<Thing>.ts` and `use<Thing>.test.ts` per composable | Reusable feature logic combining API, state and reactivity. Most feature behaviour lives here. |
| `stores/` | `<thing>.store.ts` and `<thing>.store.test.ts` | State that outlives a single view or is shared between views of the same feature. |
| `types/` | `<thing>.types.ts`, `index.ts` | Types specific to this feature. |
| `views/` | One folder per routed page: `<Name>View.vue`, `<Name>View.scss`, `<Name>View.test.ts`, `index.ts` | Routed pages. A view composes components and composables and holds little logic of its own. |
| `locales/` | `en.json`, `it.json`, one file per supported language | The feature's own translations, namespaced by the feature name. |
| `routes.ts` | single file | The feature's routes, with role requirements, titles and public marks. The only way a feature becomes reachable. |
| `index.ts` | single file | The feature's public surface. Everything outside imports only through it. |

### 9.7 The component folder: files each one should hold

Applies to shared components, feature components, views and layouts.

- **`<Name>.vue`**: the template and component logic. Layout and spacing use Tailwind utilities here.
- **`<Name>.scss`**: the component's **own stylesheet, next to the component**. Responsible for what utilities express badly: states and transitions, pseudo-elements, complex selectors, keyframes, shaped or angled backgrounds, and theme-specific refinements. The component's style block references this sibling file. It is scoped to the component, imports the abstracts through the single forwarding file, and uses tokens only. Views and layouts have one as well.
- **`<Name>.types.ts`**: props, emits and slot types. Omitted for trivial components.
- **`<Name>.test.ts`**: unit tests (see section 14).
- **`<Name>.stories.ts`**: optional documentation and visual-review story, mainly for shared components.
- **`index.ts`**: re-export so consumers import from the folder.

### 9.8 `src/sdk/` (the contract for feature apps)

Deliberately tiny and treated as a versioned public API.

- **`define-app.ts`**: the helper a feature app uses to declare its manifest with full type checking.
- **`manifest.types.ts`**: the shape of a manifest: id, title, icon name, base path, navigation, routes, required roles, optional locale and style entries.
- **`nav.types.ts`**: navigation items and groups the shell renders.
- **`route-meta.types.ts`**: route metadata: allowed roles, page title, layout choice, public mark.
- **`permissions.ts`** and its test: role and permission helpers for showing or hiding UI. Convenience only, never security.
- **`index.ts`**: the allow-list of what feature apps may import from the sdk.

### 9.9 `src/shared/` (reusable, feature-agnostic)

If it knows the name of a feature or a business entity, it does not belong here.

**`components/`** is grouped by role. Allowed dependency direction: primitives, then forms, overlays, data and feedback, then layout and navigation. Each category has an `index.ts` re-exporting its components.

- **`primitives/`**: smallest building blocks (button, input, select, checkbox, icon...). Each follows the component folder pattern of 9.7.
  - **`Icon/`** is the **only** way icons are rendered. It draws icons from the self-hosted Material icon set. It carries `icons.json`, core's own list of icon names; the full list of allowed names is the union of every app's list, generated at build time, so an unknown name fails at compile time.
  - **`Logo/`** renders the brand symbols (logo, wordmark) from `assets/brand/`.
- **`forms/`**: field wrappers, groups, labels, error display, validation presentation.
- **`overlays/`**: modal, drawer, popover, tooltip, dropdown. Own focus handling, stacking and dismissal.
- **`data/`**: table, list, pagination, badge, avatar.
- **`feedback/`**: toasts, skeletons, spinners, empty and error states, and the `ConnectionBanner` shown when the connection is lost mid-session (driven by the online-status composable and the request client's network-error reporting).
- **`navigation/`**: tabs, breadcrumbs, sidebar, navbar building blocks. They render whatever navigation data they receive.
- **`layout/`**: page container, stacks, grids, cards.

**`frappe/`** holds everything that talks to Frappe. Nothing imports from features.

- **`client.ts`** (+ test): request layer. Attaches the CSRF token, normalises responses, maps server errors to a uniform type, sends the user to login when the session has expired, and reports network failure so the connection banner can appear.
- **`call.ts`**: the single entry for invoking whitelisted server methods by name.
- **`resource.ts`** (+ test): reactive helpers for documents and lists, with loading and error state.
- **`session.ts`**: reads boot data injected by the portal page.
- **`realtime.ts`**: socket connection and subscription management.
- **`permissions.ts`**: client-side document permission checks for UX only.
- **`types.ts`**: documents, list responses, server errors.
- **`index.ts`**: public surface of the folder.

**Other shared folders**

- **`composables/`**: generic hooks with no domain meaning, each with a test, plus `index.ts`.
- **`stores/`**: application-wide state not owned by a feature (theme, sidebar), each with a test.
- **`directives/`**: reusable DOM behaviours, each with a test, plus `index.ts`.
- **`utils/`**: pure functions grouped by theme (formatting, dates, strings, validators), each with a test, plus `index.ts`.
- **`constants/`**: enums and fixed values grouped by theme: storage keys, limits, role names, plus `index.ts`.
- **`types/`**: cross-cutting types not tied to Frappe or a feature.
- **`i18n/`**: `index.ts` (translation entry); `merge-locales.ts` and its test (merges the locale files of core, every platform feature, every app and every app feature, resolving collisions); `languages.ts` and its test (the language registry: each supported language with its script and text direction, which also drives typography); `apply-language.ts` and its test (marks the document with the active language so typography and accessibility follow); and `locales/` with core's common strings.

### 9.10 Styling: three levels

Styles are **not** only in core. They exist at three levels, each with a clear owner.

| Level | Location | Owner | Holds |
|---|---|---|---|
| **Global** | `core/frontend/src/styles/` | Core only | Tokens, themes, typography, fonts, reset, Tailwind layers, vendor overrides |
| **Component** | Next to every component, view and layout (`<Name>.scss`) | Whoever owns the component, in core or any app | Component-specific design, using tokens only |
| **App-scoped** (optional) | `<app>/frontend/styles/` | The feature app | An app entry stylesheet and a small theme file, applied only under that app's root and loaded with that app's chunk |

Why global styles stay in core: tokens, themes and typography must have one source of truth, otherwise light/dark switching, brand changes and typography drift apart across apps.

What a feature app may and may not do at the app level:

- It may add app-scoped partials for things unique to that app (a dashboard grid, a print layout).
- It may adjust **only the tokens that core explicitly marks as app-themable** (for example an accent color), through the `_app-themable.scss` list in core's themes folder.
- It may not define fonts, change typography scales, override other tokens, or restyle shared components globally.

Global style files:

- **`main.scss`**: the single entry imported once by the application entry; pulls in tokens, base styles and Tailwind layers in order.
- **`tailwind.css`**: declares Tailwind's base, component and utility layers.
- **`abstracts/`**: tools that emit no CSS: `_variables.scss` (breakpoints, spacing constants), `_mixins.scss`, `_functions.scss`, and `_index.scss` as the single forwarding point.
- **`base/`**: `_reset.scss` (the normalisation baseline) and `_elements.scss` (applies type roles to body, headings and links).
- **`typography/`**: the typography system described in 9.11: `typefaces/` (one file per typeface), `scripts/` (one file per script), `devices/` (desktop and mobile scales), `_roles.scss`, `_resolve.scss` and `_index.scss`.
- **`themes/`**: `_tokens.scss` (the only place raw non-typographic values are defined: palette, radii, shadows, spacing; typography values come from the typography folder), `_app-themable.scss` (which tokens apps may override and how they are scoped), `_light.scss` and `_dark.scss` (values per theme; switching is a runtime attribute change).
- **`vendor/`**: overrides for third-party libraries, isolated so they are easy to remove.

When to use Tailwind versus the component's SCSS file: layout, spacing, sizing and simple colors go in utilities in the template; anything stateful, animated, shaped or selector-heavy goes in the component's SCSS. Both resolve every value from tokens.

### 9.11 Typography system

Components ask for a **type role** (for example "body" or "heading 2"). The system resolves that role to a concrete font, size, line height, letter spacing and weight from two inputs it detects by itself: the **script** of the text (derived from the language) and the **device class** (derived from the viewport). Nothing in a component ever branches on language or device.

**Building blocks**

| Block | Location | Responsibility |
|---|---|---|
| Language registry | `shared/i18n/languages.ts` | Every supported language declares its script and text direction. The single source of truth for "which language uses which script" |
| Language applier | `shared/i18n/apply-language.ts` | Marks the document with the active language whenever it changes. Content in another language inside a page can carry its own language marking and gets the right rules too |
| Typeface files | `styles/typography/typefaces/` | **One file per typeface** (see below) |
| Script files | `styles/typography/scripts/` | One file per script: text rules that are independent of any typeface |
| Device files | `styles/typography/devices/` | One file per device class: the base size scale |
| Roles | `styles/typography/_roles.scss` | The named type roles and how each relates to the device scale |
| Resolver | `styles/typography/_resolve.scss` | The only place that combines script, typeface and device and publishes the result as runtime variables |
| Entry | `styles/typography/_index.scss` | Forwards everything in the right order; imported once by `main.scss` |

**What each file declares**

- **A typeface file** (for example the Noto Sans file) declares:
  - the font files for each script, including their unicode-range slices;
  - the family name for each script and the fallback order: the script's own face first, then the Latin face, then the other scripts' faces, then a generic family. This makes mixed-language text render correctly glyph by glyph;
  - for **each script, a desktop profile and a mobile profile**: which weights are available and used, the size adjustment that equalises visual size between scripts, and optical refinements.
  - Scripts covered now: Latin, Japanese, Chinese (simplified and traditional). More scripts are added by extending the same file.
- **A script file** declares typeface-independent rules for that script, each with desktop and mobile values: line-height tendency, letter-spacing, line-breaking and word-breaking behaviour, whether italics and capitalisation are allowed, figure and punctuation settings.
- **A device file** declares the base size and scale for every role on that device, plus minimum sizes. Desktop and mobile are separate files, switched by the breakpoints defined in the abstracts.
- **Precedence** (applied only by the resolver): the typeface profile decides family, weights and size adjustment; the script rules decide spacing and breaking; the device scale decides sizes.

**What happens at runtime**

1. The user changes language (or the page loads); the language applier marks the document.
2. The resolver's variables are scoped by language marking and by breakpoint, so any element carrying its own language marking gets that script's rules, not only the document as a whole.
3. Role styles read those variables. Changing language or resizing the viewport changes the variables and everything follows, with no script logic and no re-render.

**How components consume it**

- Through the type roles exposed as Tailwind text utilities, or through the single role helper in the abstracts for component SCSS.
- Never by setting font family, size, line height or letter spacing directly. Style linting forbids it.
- App-scoped styles cannot alter typography.

**How to extend it**

| Change | What to do |
|---|---|
| New typeface | Add its font files under `assets/fonts/<typeface>/<script>/`, create **one typeface file**, register it in the typefaces index, point the font token at it |
| New script (for example Korean) | Download the script's face, add its folder, add **one script file**, add the script's desktop and mobile profiles in every typeface that supports it, register the languages that use it |
| New language with an existing script | One registry entry plus locale files. No typography change |
| New device class (for example tablet) | Add one device file and its breakpoint; every typeface profile and script file must then provide values |
| New role | Add it to the roles; every device file must give it a size |

The typography contract test (section 14.4) fails if any script, device, role or font file is missing, so extensions stay complete and consistent.

### 9.12 Fonts and icons (downloaded from Google, self-hosted)

**Fonts: Noto Sans from Google Fonts**

| Script | Google Fonts family | Folder under `assets/fonts/noto-sans/` | Note |
|---|---|---|---|
| Latin | Noto Sans | `latin/` | Includes Latin extended; add Greek, Cyrillic or Vietnamese slices only if needed |
| Japanese | Noto Sans JP | `japanese/` | |
| Chinese, simplified | Noto Sans SC | `chinese-simplified/` | Separate font from traditional |
| Chinese, traditional | Noto Sans TC | `chinese-traditional/` | A Hong Kong variant is another separate family if ever needed |
| More scripts later | One Google Fonts family per script (for example Korean, Arabic, Devanagari, Thai) | One new folder each | Each also needs a script file and typeface profiles (9.11) |

1. Download each family from Google Fonts, preferring variable fonts.
2. **Keep the unicode-range slices** Google provides. CJK families are very large; slices let the browser fetch only the pieces a page actually uses.
3. Keep only the weight range actually used.
4. Store them under `assets/fonts/noto-sans/<script>/`, with the license file (SIL Open Font License) and a source note at the typeface folder level recording which family each script came from, the download date and the slice list.
5. Declare them only in the typeface file, never in components.
6. Preload only the critical body font of the default language; other scripts load on demand. Files are content-hashed and cached for a long time by the normal HTTP cache.

No page or stylesheet ever calls Google's servers at runtime.

**Icons: Google Material icons**

1. Download the Material icon set from Google (the current Material Symbols family) in the style variant chosen for the brand (outlined, rounded or sharp) and the weight and fill settings you need.
2. Store the downloaded files in `assets/icons/material-symbols/` with the license file and a source note.
3. Every app (core, each feature app, the website) lists the icon names it uses in its own `icons.json` file. The build merges all lists into one union and subsets the icon set to it.
4. Choose one delivery format for the whole system: a single icon font subset (simplest, supports fill and weight variation), or individual vector files (no flash of missing icons, tree-shaken per use).
5. In the portal, render icons exclusively through the `Icon` primitive. Its allowed names are generated from the merged union, so an unknown name fails at compile time. Brand symbols (logo, wordmark) are rendered through the `Logo` primitive from `assets/brand/`.

The favicon files in `public/` are separate: they come from the brand logo, not from Material.

### 9.13 Shared assets for feature apps and the website (icons and symbols)

Icons and brand symbols must be usable by everything on the site, including code that is not part of the Vue build.

| Consumer | How it gets icons and symbols |
|---|---|
| Core components | The `Icon` and `Logo` primitives |
| Feature apps | The same primitives through the shared alias. A feature app adds icons by listing them in its own `icons.json`; it never copies files and never edits core |
| Public website app | Static files published by core, linked from the website's templates |

How the website gets them:

- The build plugin `emit-shared-assets.ts` merges every app's `icons.json` (core, feature apps and the website's own) into one union and emits a **static bundle** into core's `public/shared-assets/`: individual vector files for each icon, a ready-to-link stylesheet or sprite for use in plain HTML, the brand symbol files, and a small manifest carrying a version.
- The bundle is served by Frappe under core's assets path. The website is on the same site and origin, so no cross-origin setup is needed.
- File names are stable. The website's page controller reads the manifest and appends the version to the links so browsers refresh after a core rebuild.
- The website depends only on these published static files, never on core's code. It therefore requires core to be installed and built; declare that dependency on the website app.
- The same bundle can also carry the font files and a standalone typography stylesheet if the website should one day match the portal. This is not included by default, since the website keeps its own fonts.
- The icons contract test (section 14.4) verifies that every listed name exists in the Material set, in every app including the website.

### 9.14 Internationalisation and locale files

Translations live **in core** and also next to the code that owns the text. They are namespaced and merged at build time.

| Location | Holds | Owner |
|---|---|---|
| `shared/i18n/locales/` | Common strings used everywhere: generic buttons, statuses, validation messages, date and number labels | Core |
| `platform/<feature>/locales/` | Strings of core's own features (login, launcher) | Core |
| `<app>/frontend/locales/` | App-wide strings: app name, navigation labels | The feature app |
| `<app>/frontend/features/<feature>/locales/` | Strings of one feature | The feature app |

- Each language has one file per location. All locations support the same language set.
- Keys are namespaced by app and feature, so merging cannot collide.
- Resolution order: feature, then app, then core common, then the default language.
- Shared components get their default texts from the core common strings and accept overrides through props or slots; they never ship their own locale files.
- A contract test checks that every language file has the same keys (section 14).

### 9.15 Remaining `src/` files

- **`assets/images/`**: logos and illustrations bundled with the app.
- **`registry.d.ts`**: type declarations for the virtual registry module.
- **`env.d.ts`**: build-environment and module type declarations.

### 9.16 `core/` (Python package)

- **`__init__.py`, `modules.txt`, `patches.txt`, `config/`**: standard Frappe app scaffolding. No business logic.
- **`hooks.py`**: declares the route rule that sends all portal paths to the portal page, plus core-level hooks.
- **`api/apps.py`**: the authenticated app-list method. Reads installed apps' declarations, filters by the current user's roles, returns only what that user may see.
- **`api/session.py`**: boot and session information for the frontend. Returns only what the current session may know.
- **`tests/`**: backend tests (section 14).
- **`public/shared-assets/`**: generated static bundle of icons and brand symbols for consumers outside the Vue build, such as the website (section 9.13). Never edited by hand.
- **`public/frontend/`**: build output. Generated, never edited by hand, excluded from version control.
- **`www/portal.html`**: the portal entry page copied from the build, with a placeholder that receives boot data.
- **`www/portal.py`**: the page controller. Injects the CSRF token and boot data, and redirects guests away from every non-login portal path while remembering the destination.
- **`package.json` (app root)**: top-level scripts delegating to the frontend project.

### 9.17 Feature app frontend (example: `hr`)

Source only. A feature app contains no build tooling; core builds and tests it.

- **`manifest.ts`** and **`manifest.test.ts`**: the app's single entry for core. Declares identity, icon name, base path, navigation and the routes aggregated from its features, each with required roles. The test checks the manifest against the sdk rules.
- **`features/<feature>/`**: one folder per business capability following 9.6 (for example `leave-requests/`, `expense-claims/`).
- **`shared/`**: parts reused by two or more features of this app only. Promoted to core's shared layer only when another app needs them.
- **`icons.json`**: the icon names this app uses; merged into the shared union at build time (see 9.12 and 9.13).
- **`styles/`**: optional app-scoped styles (see 9.10): `app.scss` and `_theme.scss`.
- **`locales/`**: app-wide translations (see 9.14).
- **`tests/e2e/specs/`**: the app's end-to-end journeys. Core's Playwright configuration discovers them, so the app owns its tests and core runs them.

### 9.18 Feature app Python package

- **`hooks.py`**: registers the app in the launcher (id, title, icon name, portal route, allowed roles).
- **`api/`**: one module per frontend feature with the whitelisted methods it calls. Validates input, checks roles and permissions, returns data shaped for the UI. No method allows guest access.
- **`tests/`**: one test module per API module (section 14).
- **`<app>/doctype/`**: the standard Frappe doctypes with their permission rules.

### 9.19 Public website app (`site`)

An ordinary Frappe website app. Outside the Vue build, shares no code with it, and does not register in the launcher.

- **`hooks.py`**: sets the home page if needed and website route rules. No portal logic.
- **`www/`**: public pages (home, jobs, news...), each with a template and an optional controller that renders public data on the server, which is best for search engines and speed. The home page holds the portal button.
- **The portal button**: a plain link to the portal root. If the visitor has no session, the login wall sends them to login and returns them to the launcher afterwards; with a session they land on the launcher directly. Changing its label based on login state is cosmetic only.
- **`api/public.py`**: the only guest-reachable methods in the whole site. Each returns only public-safe fields of published records, is rate limited, and caches read-heavy results. Kept separate from core's authenticated APIs so guest exposure is obvious and reviewable.
- **`public/`**: the site's own SCSS sources, compiled CSS, scripts, images and fonts.
- **`icons.json`**: the icon names the website uses; merged into the shared union and verified by the icons contract test.
- **`templates/`**: shared page fragments (header, footer, cards). They link to core's published shared-assets bundle for icons and brand symbols.
- **`tests/test_public_api.py`**: verifies that only published, public-safe data is returned and that rate limits apply.

---

## 10. Colocation and naming rules (summary)

- A component, view or layout is a folder: template, SCSS, types, test, optional story, re-export.
- A unit's test sits next to the unit. Cross-cutting tests live in `tests/`.
- A feature's translations live in the feature; an app's in the app; common ones in core.
- Naming: capitalised names for components and views, a `use` prefix for composables, a `.store` suffix for state modules, an `.api` suffix for API modules, a `.types` suffix for type files, a `.test` suffix for tests, an underscore prefix for Sass partials.
- Re-export files exist at feature, component-folder and category boundaries only.

---

## 11. Who owns what

| Concern | Core | Feature app | Public site app |
|---|---|---|---|
| Vue shell, router, layouts | Owns | Uses | n/a |
| Login pages and session | Owns | Uses | Links to it |
| App launcher | Owns | Registers into it | Links to it |
| Shared components | Owns | Uses; may add app-local shared parts | n/a |
| Typography system (typefaces, scripts, devices, roles) | Owns | Consumes roles; cannot alter | Own fonts unless it links to core's bundle |
| Global theme, palette | Owns | Consumes tokens; may adjust app-themable tokens | Own styles |
| Component styles | Own components | Own components | Own styles |
| Fonts and Material icons | Owns the downloaded files | Uses through core; lists its icons in `icons.json` | Links to core's published icons and brand symbols; lists its icons in `icons.json` |
| Translations | Common and own features | App-wide and own features | Own pages |
| Navigation of an app | Renders | Declares | n/a |
| Features, views | Auth and launcher | Owns | Own pages |
| Business APIs and permissions | Own endpoints | Owns | Public read-only endpoints |
| Test infrastructure | Owns runners and shared helpers | Writes its own tests, run by core | Backend tests only |
| Public data (jobs, news) | n/a | n/a | Owns |

---

## 12. Guardrails

- Enforce the dependency rules with lint boundaries, not conventions.
- Run a continuous-integration build of core together with all feature apps, since build-time coupling means one app's type error blocks everyone.
- Lazy-load every app and feature route.
- Keep the sdk tiny and change it deliberately.
- Never rely on hidden routes or hidden menu items for security.
- Keep guest-reachable endpoints in one clearly named module and review it on every change.
- No raw colors, font sizes or font names outside the token files; style linting enforces it.
- Components never set font family, size, line height or letter spacing directly; they use type roles.
- Every app lists the icons it uses in its own `icons.json`; nobody copies icon files by hand.
- No runtime requests to third-party font or icon hosts.

---

## 13. Checklist: adding a new feature app

1. Create the Frappe app and install it on the site.
2. Declare its launcher registration (id, title, icon name, route, roles) in its hooks file.
3. Create its manifest in the frontend folder, using core's sdk.
4. Build features as slices, each with its own routes, locales, tests and component folders.
5. Add the matching whitelisted Python modules with role checks, without guest access, and their backend tests.
6. List the icons the app uses in its `icons.json`, and optionally add app-wide locales and an app-scoped style folder.
7. Add end-to-end specs for the app's main journeys.
8. Rebuild core. The discovery plugin picks the app up, and the launcher shows it to users whose roles match.

---

## 14. Testing strategy

### 14.1 Layers

| Layer | What it proves | Tooling category | Where it lives |
|---|---|---|---|
| **Static checks** | Types are sound, architecture boundaries hold, styles use tokens | Type checker, linter with boundary rules, style linter | Config at the frontend root; run on every change |
| **Unit tests** | One unit behaves correctly in isolation: utilities, composables, stores, API modules, components | Vitest with Vue Test Utils | Next to the unit (`*.test.ts`) |
| **Integration tests** | Several units work together: router with guards and session, registry with manifests, feature views with stores and mocked backend | Vitest with a mocked network layer | `tests/integration/` |
| **Contract tests** | The agreements between core and apps hold | Vitest | `tests/contract/` |
| **End-to-end tests** | Real journeys work against a real bench and site | Playwright | `tests/e2e/` in core; `<app>/frontend/tests/e2e/` in apps |
| **Backend tests** | Server rules hold: permissions, guest rejection, filtering, public data safety | Frappe's test runner | `<app>/tests/` |
| **Visual and accessibility checks** (optional) | Shared components render consistently and meet accessibility rules | Stories with visual comparison; automated accessibility scans | Next to shared components; scans also run inside unit and e2e tests |

### 14.2 Unit tests, by folder

- **`utils/`, `directives/`, `composables/`**: input/output behaviour, edge cases, cleanup on unmount. No network, no DOM beyond what the unit needs.
- **`stores/`**: state transitions and derived values, with the API layer replaced by a fake.
- **`api/` modules**: that each function sends the right request and maps the response, with the request client replaced by a fake. Error mapping is covered here.
- **`shared/frappe/`**: CSRF header attached, error mapping, expired-session handling, resource loading and error states.
- **Components, views, layouts**: rendering by props and slots, emitted events, keyboard and focus behaviour (especially overlays), state classes, and an automated accessibility scan. Texts are asserted through translation keys, not literal strings.
- **`sdk/permissions`**: every role/permission helper case.

### 14.3 Integration tests (`tests/integration/`)

- **`login-wall`**: a guest visiting the launcher or any app route is sent to login with the destination remembered; after login the user lands on the remembered internal path; an external redirect target is refused; a logged-in user visiting login goes to the launcher.
- **`role-guard`**: a user without the required role cannot open an app route; a user with the role can.
- **`registry`**: the launcher shows the intersection of registered apps and the server's list, including the cases of an installed-but-unbuilt app and a built-but-not-permitted app.

They use shared helpers from `tests/utils/` (a rendering helper that installs providers, a fake session, a fake router) and a mocked network layer from `tests/mocks/` (handlers per feature area and sample data in `fixtures/`).

### 14.4 Contract tests (`tests/contract/`)

- **`typography`**: every language in the registry maps to a script that has typeface profiles for every device; every typeface covers every registered script on desktop and mobile; every role resolves for every script and device; every referenced font file exists.
- **`icons`**: every icon name listed in any `icons.json` (core, feature apps, website) exists in the Material set, and the generated name types match the merged union.
- **`manifests`**: every discovered app manifest is valid: unique id, base path inside the portal, declared roles, navigation items pointing to existing routes, icon names present in the allowed icon list, locale and style entries existing.
- **`locales-parity`**: every language file in every location has exactly the same keys as the default language, with no unused or missing keys.
- **`tokens`**: every token used by the Tailwind preset exists in the token files, every theme defines every token, and apps override only tokens listed as app-themable.

Boundary rules (no app-to-app imports, no bypass of a feature's public file) are verified by the linter in the static layer.

### 14.5 End-to-end tests (`tests/e2e/`)

- **`global-setup.ts`**: prepares the test site: seeded users for each relevant role, seeded sample records, and stored logged-in sessions so specs do not log in every time.
- **`fixtures/`**: the logged-in-as-role fixtures and seeded data handles.
- **`pages/`**: page objects for login, launcher and app shell, so specs describe behaviour, not selectors.
- **`specs/`**: journeys, run on a desktop and a mobile viewport:
  - guest opens the launcher and is redirected to login, then returns after login
  - launcher shows exactly the apps allowed for each role
  - opening an app, navigating its sidebar, switching back to the launcher
  - direct URL to an app the role cannot access
  - session expiry during use sends the user to login
  - connection lost mid-session: the in-app banner appears and clears when the connection returns
  - after a deploy: an open tab that hits a missing lazy chunk reloads once and recovers
  - public website: the portal button leads to login for guests and to the launcher for logged-in users
- Feature apps add their own specs in their own `tests/e2e/specs/`; core's configuration discovers and runs them together with core's.

### 14.6 Backend tests

Each Python package has a `tests/` folder with one test module per API module.

- **core**: the app-list method rejects guests, returns only apps whose roles match, and reflects installed apps; the session method returns only what the session may know; the portal page controller redirects guests on non-login paths and sets nothing user-specific for guests.
- **feature apps**: every whitelisted method rejects guests, enforces role and document permissions, validates input, and returns the expected shape.
- **public site app**: every guest method returns only published, public-safe fields, honours rate limits, and returns cached data correctly.

### 14.7 Test data and environments

- **Frontend fixtures** (sample users, roles, app lists, documents) live in `tests/mocks/fixtures/` and are shared by unit, integration and mocked-network tests.
- **End-to-end data** is seeded on a dedicated test site, never a real one, and reset between runs.
- **Feature apps** reuse core's helpers and fixtures through the same alias mechanism as the sdk.

### 14.8 Continuous integration order

1. Type check, lint (including boundary rules) and style lint.
2. Unit tests.
3. Integration and contract tests.
4. Build core with all apps.
5. Backend tests on a bench.
6. End-to-end tests against the built portal on the test site.
7. Optional: visual and accessibility reports.

### 14.9 Coverage expectations

- Aim high for `utils`, `shared/frappe`, `sdk`, router guards and stores, where logic is dense.
- Moderate for components and views, where behaviour matters more than line counts.
- Every guest-reachable and role-restricted endpoint must have a backend test; this is a rule, not a percentage.
- Every critical journey in section 14.5 must exist as an end-to-end spec.