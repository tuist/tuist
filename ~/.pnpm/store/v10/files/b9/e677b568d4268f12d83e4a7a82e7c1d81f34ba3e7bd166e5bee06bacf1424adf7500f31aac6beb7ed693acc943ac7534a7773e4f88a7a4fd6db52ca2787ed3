function l(t) {
  var o, i;
  if (!t)
    return {};
  const n = (
    // OpenAPI 3.x
    Object.keys(((o = t == null ? void 0 : t.components) == null ? void 0 : o.schemas) ?? {}).length ? (i = t == null ? void 0 : t.components) == null ? void 0 : i.schemas : (
      // Swagger 2.0
      Object.keys((t == null ? void 0 : t.definitions) ?? {}).length ? t == null ? void 0 : t.definitions : (
        // Fallback
        {}
      )
    )
  );
  return Object.keys(n ?? {}).forEach((r) => {
    var f;
    ((f = n[r]) == null ? void 0 : f["x-internal"]) === !0 && delete n[r];
  }), n;
}
export {
  l as getModels
};
