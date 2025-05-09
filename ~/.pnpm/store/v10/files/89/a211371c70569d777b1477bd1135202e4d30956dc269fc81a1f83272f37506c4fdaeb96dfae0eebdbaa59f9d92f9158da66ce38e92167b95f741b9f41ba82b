import { isDocument as n } from "./isDocument.js";
import { parse as t } from "yaml";
function a(r) {
  if (!n(r))
    return !1;
  try {
    const e = JSON.parse(r ?? "");
    return typeof (e == null ? void 0 : e.openapi) == "string" ? `OpenAPI ${e.openapi} JSON` : typeof (e == null ? void 0 : e.swagger) == "string" ? `Swagger ${e.swagger} JSON` : !1;
  } catch {
  }
  try {
    const e = t(r ?? "");
    return typeof (e == null ? void 0 : e.openapi) == "string" ? `OpenAPI ${e.openapi} YAML` : typeof (e == null ? void 0 : e.swagger) == "string" ? `Swagger ${e.swagger} YAML` : !1;
  } catch {
  }
  return !1;
}
export {
  a as getOpenApiDocumentVersion
};
