const c = ["oneOf", "anyOf", "allOf", "not"];
function y(o) {
  var s;
  if (!o || typeof o != "object")
    return o;
  let r = { ...o };
  const t = c.find((i) => r == null ? void 0 : r[i]);
  if (!t || t === "not")
    return r;
  const f = r == null ? void 0 : r[t];
  if (!Array.isArray(f))
    return r;
  f.some((i) => i.type === "null") && (r.nullable = !0);
  const n = f.filter((i) => i.type !== "null");
  return n.length === 1 && (r != null && r[t]) ? (r = { ...r, ...n[0] }, r == null || delete r[t], r) : (Array.isArray(r == null ? void 0 : r[t]) && ((s = r == null ? void 0 : r[t]) == null ? void 0 : s.length) > 1 && (r[t] = n), r);
}
export {
  c as discriminators,
  y as optimizeValueForDisplay
};
