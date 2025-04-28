function n(r) {
  const t = /{{?\s*([\w.-]+)\s*}}?/g, s = r == null ? void 0 : r.matchAll(t);
  return Array.from(s ?? [], (c) => c[1]);
}
export {
  n as getVariableNames
};
