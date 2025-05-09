const s = (r) => typeof r != "string" ? !1 : !!i.parseSafe(r, !1), i = {
  /** Parse and throw if the return value is not an object */
  parse: (r) => {
    const t = JSON.parse(r);
    if (typeof t != "object") throw Error("Invalid JSON object");
    return t;
  },
  /** Parse and return a fallback on failure */
  parseSafe(r, t) {
    try {
      return i.parse(r);
    } catch (e) {
      return typeof t == "function" ? t(e) : t;
    }
  },
  stringify: (r) => JSON.stringify(r)
}, f = (r) => {
  if (typeof r == "string")
    return s(r) ? JSON.stringify(JSON.parse(r), null, 2) : r;
  if (typeof r == "object")
    try {
      return JSON.stringify(r, null, 2);
    } catch {
      return o(r);
    }
  return r.toString();
};
function o(r) {
  const t = /* @__PURE__ */ new Set();
  return JSON.stringify(
    r,
    (e, n) => {
      if (typeof n == "object" && n !== null) {
        if (t.has(n))
          return "[Circular]";
        t.add(n);
      }
      return n;
    },
    2
  );
}
const c = (r) => new Promise((t) => setTimeout(t, r));
export {
  f as prettyPrintJson,
  c as sleep
};
