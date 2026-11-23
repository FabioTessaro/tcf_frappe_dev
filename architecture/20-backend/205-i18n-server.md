# 205 · Server-side and Desk translations

## Purpose

How strings outside the portal are translated, and how strings shared by portal and server are
kept in one source of truth.

## String domains

| Domain | Examples | Source of truth | Runtime |
|---|---|---|---|
| Portal UI | Views, buttons, navigation | Frontend locale JSON ([10-frontend/108-i18n](../10-frontend/108-i18n.md)) | vue-i18n |
| Desk and server output | Doctype/field labels, Desk JS, emails, notifications, print formats, PDFs | `<app>/locale/*.po`, extracted by Frappe tooling | Frappe `_()` / `__()` |
| Shared | Error messages (and other catalogued messages) | The error catalog ([03-contracts/30-error-catalog](../03-contracts/30-error-catalog.md)) | Generated into both domains above |

## Rules

- `BE-I18N-001` Server-side user-facing strings MUST be wrapped in `_()` (Python) or `__()` (Desk
  JS) and extracted with `bench generate-pot-file` into `<app>/locale/main.pot`.
- `BE-I18N-002` Translations of catalogued messages MUST be authored once and generated into both
  the portal `errors.*` namespace and the `.po` files; generated entries MUST NOT be edited by hand.
- `BE-I18N-003` Emails, notifications and documents sent to a user MUST be rendered in the
  recipient's language, not the sender's.
- `BE-I18N-004` Every app MUST support the same language set as the portal.
- `BE-I18N-005` Translators MUST use the self-hosted translation tool (Weblate), connected to the
  JSON and PO files of each repository; translations flow back as pull requests.

## Verification

CI: `.pot` up to date; every `.po` complete for catalogued messages; generated-artifacts check.
