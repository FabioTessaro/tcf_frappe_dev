# Playbook · New language or script

**New language using an existing script**

1. Add the language to `shared/i18n/languages.ts` with script and direction.
2. Add the language file in every portal locale location (`FE-I18N-004`) and `.po` files in every
   app (`BE-I18N-004`); create the language in the translation tool.
3. Contract tests `locales-parity` and `typography` must pass.

**New script**

1. Follow the typography extension table ([106-typography](../10-frontend/106-typography.md)):
   font folder, script file, profiles in every typeface, language registration (`FE-TYP-003`).
2. Then the steps above.
