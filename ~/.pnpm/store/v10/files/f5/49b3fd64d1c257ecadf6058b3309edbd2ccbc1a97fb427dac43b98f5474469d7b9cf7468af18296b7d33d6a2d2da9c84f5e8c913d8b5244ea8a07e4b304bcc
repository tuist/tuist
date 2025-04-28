import { convert as e } from "@scalar/postman-to-openapi";
function s(t) {
  var n, o;
  try {
    const r = JSON.parse(t);
    return ((n = r.info) == null ? void 0 : n._postman_id) !== void 0 && new URL((o = r.info) == null ? void 0 : o.schema).host === "schema.getpostman.com";
  } catch {
    return !1;
  }
}
async function a(t) {
  try {
    const n = JSON.parse(t), o = e(n);
    return JSON.stringify(o, null, 2);
  } catch {
    throw new Error("Failed to convert Postman collection to OpenAPI");
  }
}
function l(t) {
  var n, o;
  try {
    if (s(t)) {
      const r = JSON.parse(t);
      return {
        type: "json",
        title: ((n = r.info) == null ? void 0 : n.name) || "Postman Collection",
        version: ((o = r.info) == null ? void 0 : o.version) || "1.0"
      };
    }
    return null;
  } catch {
    return null;
  }
}
export {
  a as convertPostmanToOpenApi,
  l as getPostmanDocumentDetails,
  s as isPostmanCollection
};
