# 107 · Fonts, icons and shared assets

## Fonts: Noto Sans, self-hosted

| Script | Google Fonts family | Folder under `assets/fonts/noto-sans/` |
|---|---|---|
| Latin (incl. Latin extended) | Noto Sans | `latin/` |
| Japanese | Noto Sans JP | `japanese/` |
| Chinese simplified | Noto Sans SC | `chinese-simplified/` |
| Chinese traditional | Noto Sans TC | `chinese-traditional/` |
| Later scripts | One family per script | One folder each |

- `FE-FONT-001` Fonts MUST be downloaded once (variable fonts preferred), keeping Google's
  unicode-range slices and only the weight range used, stored with `LICENSE.txt` (SIL OFL) and
  `SOURCE.md` (family per script, download date, slice list).
- `FE-FONT-002` Fonts MUST be declared only in typeface files.
- `FE-FONT-003` Only the critical body font of the default language is preloaded; other scripts
  load on demand. Files are content-hashed and cached long-term.
- `FE-FONT-004` No page or stylesheet may call Google's (or any third party's) servers at runtime.

## Icons: Material Symbols, self-hosted

- `FE-ICON-001` The Material Symbols set is downloaded in one style variant (outlined, rounded or
  sharp) with the chosen weight and fill, stored in `assets/icons/material-symbols/` with licence
  and source note.
- `FE-ICON-002` Every app (core, feature apps, site app) lists the icon names it uses in its own
  `icons.json`. The build merges them into one union and subsets the icon set.
- `FE-ICON-003` One delivery format for the whole system: **a single subset icon font** (supports
  fill and weight variation). Changing it requires a guide change.
- `FE-ICON-004` In the portal, icons MUST be rendered only through the `Icon` primitive; allowed
  names are generated from the union so an unknown name fails type checking. Brand symbols are
  rendered through the `Logo` primitive from `assets/brand/`.
- `FE-ICON-005` Favicons in `public/` are generated from the brand logo, not from Material.

## Shared assets for the website

`emit-shared-assets.ts` emits into `<core-app>/public/shared-assets/`: the icon subset, a
ready-to-link stylesheet for plain HTML, brand symbol files, and a manifest with a version.

- `FE-ASSET-001` File names in the bundle are stable; the website appends the manifest version to
  links for cache busting.
- `FE-ASSET-002` The site app depends only on these published static files, never on core code;
  it MUST declare core in `required_apps`.
- `FE-ASSET-003` Nobody copies icon files by hand; apps only list names in `icons.json`.

## Verification

`icons` contract test: every listed name exists in the Material set (all apps incl. website) and
the generated types match the union.
