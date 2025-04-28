import { replaceTemplateVariables as t } from "../string-template.js";
function o(s, e) {
  const r = new URLSearchParams();
  return s.parameters.query.forEach((a) => {
    a.enabled && (a.type === "array" ? t(a.value ?? "", e).split(",") : [t(a.value ?? "", e)]).forEach((c) => r.append(a.key, c.trim()));
  }), r;
}
export {
  o as createFetchQueryParams
};
