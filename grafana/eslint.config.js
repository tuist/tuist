// ESLint 9 flat config — extends the shared Grafana plugin ruleset.
//
// `@grafana/eslint-config/flat` references
// `eslint-plugin-react-hooks.configs['recommended-latest']`, which only
// exists in react-hooks >= 5. The lockfile resolves an older copy that
// returns undefined, so we register the plugin explicitly ourselves and
// filter the undefined entry out of the upstream spread.
const reactHooks = require('eslint-plugin-react-hooks');
const grafanaConfig = require('@grafana/eslint-config/flat').filter(Boolean);

module.exports = [
  {
    ignores: [
      'dist/',
      'node_modules/',
      'coverage/',
      '.cache/',
      '.config/',
      'tuist-tuist-app-*.zip',
    ],
  },
  {
    plugins: {
      'react-hooks': reactHooks,
    },
  },
  ...grafanaConfig,
  {
    rules: {
      'react/prop-types': 'off',
    },
  },
  {
    files: ['src/**/*.{ts,tsx}'],
    languageOptions: {
      parserOptions: {
        project: './tsconfig.json',
      },
    },
    rules: {
      '@typescript-eslint/no-deprecated': 'warn',
    },
  },
];
