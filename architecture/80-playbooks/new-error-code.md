# Playbook · New error code

1. Add the code in the slice's `errors.py` (or `<app>_shared/errors.py` if app-wide), with HTTP
   status, params model and English template (`CT-ERR-002`).
2. Raise it through the catalog (`CT-ERR-005`).
3. `just generate`; add translations for every language in the translation tool (`CT-ERR-008`,
   `BE-I18N-002`).
4. Handle it in the frontend only if it needs special UI; otherwise the generic mapping applies
   (`FE-CLI-002`).
5. Never rename or reuse an existing code (`CT-ERR-003`).
