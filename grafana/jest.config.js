// Delegate to the full jest config scaffolded by `@grafana/create-plugin`
// at `.config/jest.config.js`. The scaffolded file refers to
// `<rootDir>/jest-setup.js`; our setup lives under `.config/` so we
// override that path here.
const path = require('path');
const base = require('./.config/jest.config');

module.exports = {
  ...base,
  setupFilesAfterEnv: [path.resolve(__dirname, '.config', 'jest-setup.js')],
};
