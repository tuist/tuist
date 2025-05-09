import { json as n, yaml as o } from "@scalar/oas-utils/helpers";
import { isUrl as i } from "./isUrl.js";
function t(r) {
  return {
    title: typeof (r == null ? void 0 : r.title) == "string" ? `${r == null ? void 0 : r.title}` : void 0
  };
}
function g(r) {
  if (!(!r || i(r))) {
    try {
      const e = n.parse(r ?? "");
      return typeof (e == null ? void 0 : e.openapi) == "string" ? {
        version: `OpenAPI ${e.openapi}`,
        type: "json",
        ...t(e.info)
      } : typeof (e == null ? void 0 : e.swagger) == "string" ? {
        version: `Swagger ${e.swagger}`,
        type: "json",
        ...t(e.info)
      } : void 0;
    } catch {
    }
    try {
      const e = o.parse(r ?? "");
      return typeof (e == null ? void 0 : e.openapi) == "string" ? {
        version: `OpenAPI ${e.openapi}`,
        type: "yaml",
        ...t(e.info)
      } : typeof (e == null ? void 0 : e.swagger) == "string" ? {
        version: `Swagger ${e.swagger}`,
        type: "yaml",
        ...t(e.info)
      } : void 0;
    } catch {
    }
  }
}
export {
  g as getOpenApiDocumentDetails
};
