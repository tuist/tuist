// Delegate to @grafana/create-plugin's shared Jest config so upstream
// changes land with `npx @grafana/create-plugin@latest update`.
module.exports = {
  preset: '@grafana/create-plugin/jest-preset',
};
