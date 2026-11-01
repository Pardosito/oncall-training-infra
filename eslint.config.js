import eslint from "@eslint/js";
import tseslint from "typescript-eslint";
import prettierConfig from "eslint-config-prettier";

// Same rules as the backend repo (CONVENTIONS §4).
export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  prettierConfig,
  {
    languageOptions: {
      parserOptions: {
        projectService: {
          allowDefaultProject: ["*.config.js", "*.config.ts", "services/*/vitest.config.ts"],
        },
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/consistent-type-imports": ["error", { prefer: "type-imports" }],
      "no-console": "error",
      "no-restricted-exports": [
        "error",
        {
          restrictDefaultExports: {
            direct: true,
            named: true,
            defaultFrom: true,
            namedFrom: true,
            namespaceFrom: true,
          },
        },
      ],
    },
  },
  {
    files: ["*.config.{js,ts,mjs}", "**/*.config.{js,ts,mjs}"],
    rules: {
      "no-restricted-exports": "off",
    },
  },
  {
    files: ["**/*.js", "**/*.mjs"],
    ...tseslint.configs.disableTypeChecked,
  },
  {
    ignores: ["**/dist/**", "**/node_modules/**", "**/coverage/**"],
  },
);
