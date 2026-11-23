# 106 · Typography system

## Purpose

Components ask for a **type role** (e.g. `body`, `heading-2`). The system resolves it to font,
size, line height, letter spacing and weight from the **script** (derived from the language) and
the **device class** (derived from the viewport). Components never branch on language or device.

## Building blocks

| Block | Location | Responsibility |
|---|---|---|
| Language registry | `shared/i18n/languages.ts` | Each language's script and text direction. Single source of truth |
| Language applier | `shared/i18n/apply-language.ts` | Marks the document (and nested content) with the active language |
| Typeface files | `styles/typography/typefaces/` | One file per typeface |
| Script files | `styles/typography/scripts/` | One file per script; typeface-independent rules |
| Device files | `styles/typography/devices/` | One file per device class; base size scale |
| Roles | `styles/typography/_roles.scss` | Named roles and their relation to the device scale |
| Resolver | `styles/typography/_resolve.scss` | The only place combining script, typeface and device into runtime variables |
| Entry | `styles/typography/_index.scss` | Forwards in order; imported once by `main.scss` |

**A typeface file** declares, per script: font files with unicode-range slices; family name and
fallback order (script face, Latin face, other scripts, generic); a desktop and a mobile profile
(weights, size adjustment, optical refinements). Scripts covered: Latin, Japanese, Chinese
simplified, Chinese traditional.

**A script file** declares (desktop and mobile values): line-height tendency, letter spacing,
line and word breaking, whether italics and capitalisation are allowed, figure and punctuation
settings.

**A device file** declares base size and scale for every role plus minimum sizes; desktop and
mobile switch at the breakpoints in the abstracts.

**Precedence** (applied only by the resolver): typeface → family, weights, size adjustment;
script → spacing and breaking; device → sizes.

At runtime, changing language or viewport changes the resolver's variables (scoped by language
marking and breakpoint); roles read those variables; no script logic, no re-render.

## Rules

- `FE-TYP-001` Components MUST consume typography only via type roles (Tailwind text utilities
  from the preset, or the role mixin in SCSS). Setting font family, size, line height or letter
  spacing directly is forbidden.
- `FE-TYP-002` App-scoped styles MUST NOT alter typography.
- `FE-TYP-003` Every registered language maps to a script with typeface profiles for every device;
  every role resolves for every script and device; every referenced font file exists.

## Extending

| Change | What to do |
|---|---|
| New typeface | Files under `assets/fonts/<typeface>/<script>/`, one typeface file, register it, point the font token at it |
| New script | Download its face, add its folder, one script file, profiles in every typeface supporting it, register its languages |
| New language, existing script | One registry entry plus locale files |
| New device class | One device file and breakpoint; every typeface profile and script file must provide values |
| New role | Add to roles; every device file must give it a size |

## Verification

Stylelint (FE-TYP-001, 002); `typography` contract test (FE-TYP-003).
