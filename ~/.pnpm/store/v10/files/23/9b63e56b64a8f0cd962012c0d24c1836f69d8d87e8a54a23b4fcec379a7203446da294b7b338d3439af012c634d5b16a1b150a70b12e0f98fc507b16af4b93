function u(e, r) {
  let t = e;
  const s = r.required && r.required.includes(e);
  return t += s ? " REQUIRED " : " optional ", r.properties[e] && (t += r.properties[e].type, r.properties[e].description && (t += " " + r.properties[e].description)), t;
}
function f(e) {
  var s;
  const r = ["Body"], t = (s = e == null ? void 0 : e.schema) == null ? void 0 : s.properties;
  return t && Object.keys(t).forEach((i) => {
    if (!e.schema)
      return;
    r.push(u(i, e.schema));
    const p = t[i];
    p.type === "object" && !!p.properties && p.properties && Object.keys(p.properties).forEach((c) => {
      var o, n;
      r.push(`${c} ${(n = (o = p.properties) == null ? void 0 : o[c]) == null ? void 0 : n.type}`);
    });
  }), r;
}
function a(e) {
  var r, t, s;
  try {
    const i = (s = (t = (r = e == null ? void 0 : e.information) == null ? void 0 : r.requestBody) == null ? void 0 : t.content) == null ? void 0 : s["application/json"];
    if (!i)
      throw new Error("Body not found");
    return f(i);
  } catch {
    return !1;
  }
}
export {
  a as extractRequestBody,
  u as formatProperty,
  f as recursiveLogger
};
