// Shared ESLint configuration (DEL-TOOL-003) — copied by `just sync-config`;
// do not edit the copy. The core app's eslint.config.js imports it and adds the
// boundary rules of its layout (eslint-plugin-boundaries, FE-STR-001/004/006).
// ESLint does not format: Prettier does.
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import vue from "eslint-plugin-vue";
import security from "eslint-plugin-security";

export default [
  js.configs.recommended,
  ...tseslint.configs.strict,
  ...vue.configs["flat/recommended"],
  security.configs.recommended,
  {
    files: ["**/*.vue"],
    languageOptions: { parserOptions: { parser: tseslint.parser } },
  },
  {
    rules: {
      "no-console": ["error", { allow: ["warn", "error"] }],
      "vue/multi-word-component-names": "off",
    },
  },
];
