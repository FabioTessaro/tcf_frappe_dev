// Shared Stylelint configuration (DEL-TOOL-003) — copied by `just sync-config`;
// do not edit the copy. Raw colours and font values are forbidden (FE-STY-001,
// FE-TYP-001); the core app's stylelint.config.js re-allows them only in token
// and typography files (FE-STY-002).
export default {
  extends: ["stylelint-config-standard-scss"],
  rules: {
    "color-no-hex": true,
    "color-named": "never",
    "function-disallowed-list": [
      "rgb",
      "rgba",
      "hsl",
      "hsla",
      "hwb",
      "lab",
      "lch",
      "oklab",
      "oklch",
    ],
    "declaration-property-value-disallowed-list": {
      "/^font(-family|-size)?$/": ["/./"],
      "line-height": ["/./"],
      "letter-spacing": ["/./"],
    },
  },
};
