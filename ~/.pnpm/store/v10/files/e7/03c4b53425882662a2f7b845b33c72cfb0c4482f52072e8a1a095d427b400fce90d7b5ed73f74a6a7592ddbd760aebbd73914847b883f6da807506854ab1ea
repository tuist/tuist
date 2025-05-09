const r = [
  ["--theme-", "--scalar-"],
  ["--sidebar-", "--scalar-sidebar-"]
], c = r.map(([e]) => e);
function o(e) {
  return c.some((a) => e.includes(a)) ? (console.warn(
    "DEPRECATION WARNING: It looks like you're using legacy CSS variables in your custom CSS string. Please migrate them to use the updated prefixes. See https://github.com/scalar/scalar#theme-prefix-changes"
  ), r.reduce((a, [s, t]) => a.replaceAll(s, t), e)) : e;
}
export {
  c as LEGACY_PREFIXES,
  r as PREFIX_MIGRATIONS,
  o as migrateThemeVariables
};
