import { replaceTemplateVariables as s } from "../string-template.js";
function l(t, o) {
  const a = {};
  return t.parameters.headers.forEach((e) => {
    const r = e.key.trim().toLowerCase();
    e.enabled && (r !== "content-type" || e.value !== "multipart/form-data") && (a[r] = s(e.value, o));
  }), a;
}
export {
  l as createFetchHeaders
};
