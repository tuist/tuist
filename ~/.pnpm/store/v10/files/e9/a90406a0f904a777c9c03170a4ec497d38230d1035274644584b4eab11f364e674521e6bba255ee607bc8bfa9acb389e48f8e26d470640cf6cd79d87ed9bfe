import { replaceTemplateVariables as e } from "../string-template.js";
import { canMethodHaveBody as c } from "@scalar/oas-utils/helpers";
function v(f, o, t) {
  var r, i, n;
  if (!c(f))
    return { body: void 0, contentType: void 0 };
  if (o.body.activeBody === "formData" && o.body.formData) {
    const y = o.body.formData.encoding === "form-data" ? "multipart/form-data" : "application/x-www-form-urlencoded", d = o.body.formData.encoding === "form-data" ? new FormData() : new URLSearchParams();
    return o.body.formData.value.forEach((a) => {
      !a.enabled || !a.key || (a.file && d instanceof FormData ? d.append(a.key, a.file, a.file.name) : a.value !== void 0 && d.append(a.key, e(a.value, t)));
    }), { body: d, contentType: y };
  }
  return o.body.activeBody === "raw" ? {
    body: e(((r = o.body.raw) == null ? void 0 : r.value) ?? "", t),
    contentType: (i = o.body.raw) == null ? void 0 : i.encoding
  } : o.body.activeBody === "binary" ? {
    body: o.body.binary,
    contentType: (n = o.body.binary) == null ? void 0 : n.type
  } : {
    body: void 0,
    contentType: void 0
  };
}
export {
  v as createFetchBody
};
