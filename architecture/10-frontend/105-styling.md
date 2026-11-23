# 105 · Styling

## Purpose

Three style levels with clear owners, design tokens and the Tailwind/SCSS split.

## Levels

| Level | Location | Owner | Holds |
|---|---|---|---|
| **Global** | `<core-app>/frontend/src/styles/` | Core only | Tokens, themes, typography, fonts, reset, Tailwind layers, vendor overrides |
| **Component** | `<Name>.scss` next to each component, view, layout | The component owner | Component design using tokens only |
| **App-scoped** (optional) | `<feature-app>/frontend/styles/` | The feature app | `app.scss` and `_theme.scss`, applied only under the app root, loaded with the app chunk |

## Global style files

- `main.scss`: the single entry, imported once by `main.ts`.
- `tailwind.css`: base, components, utilities layers.
- `abstracts/`: `_variables.scss`, `_mixins.scss`, `_functions.scss`, `_index.scss` (single
  forwarding point; emits no CSS).
- `base/`: `_reset.scss`, `_elements.scss` (applies type roles to body, headings, links).
- `typography/`: see [106-typography](106-typography.md).
- `themes/`: `_tokens.scss` (only place for raw non-typographic values: palette, radii, shadows,
  spacing), `_app-themable.scss` (tokens apps may override and how they are scoped),
  `_light.scss`, `_dark.scss` (runtime attribute switch).
- `vendor/_third-party-overrides.scss`.

## Rules

- `FE-STY-001` Components MUST NOT hardcode colours, font sizes, spacing or radii; every value
  comes from a token (Tailwind utility mapped by the preset, or token in SCSS).
- `FE-STY-002` Raw colour and font values are allowed only in token and typography files.
- `FE-STY-003` Layout, spacing, sizing and simple colours go in Tailwind utilities in the
  template; states, transitions, pseudo-elements, complex selectors, keyframes and shaped
  backgrounds go in the component's SCSS file.
- `FE-STY-004` Component SCSS MUST be scoped and import abstracts only through `_index.scss`.
- `FE-STY-005` Feature apps MAY add app-scoped partials and MAY override only tokens listed in
  `_app-themable.scss`. They MUST NOT define fonts, change typography scales, override other
  tokens or restyle shared components globally.
- `FE-STY-006` Every theme MUST define every token.

## Verification

Stylelint (FE-STY-001, 002, 004); `tokens` contract test (FE-STY-005, 006).
