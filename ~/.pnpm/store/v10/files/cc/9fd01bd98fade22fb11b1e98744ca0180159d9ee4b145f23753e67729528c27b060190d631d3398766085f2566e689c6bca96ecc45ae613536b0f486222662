import { ERRORS as n } from "../constants.js";
import { escapeJsonPointer as e } from "@scalar/openapi-parser";
function m(o) {
  o.unshift("#");
  const r = o.map((t) => e(t.trim())).filter(Boolean).join("/");
  if (r === "#")
    throw new Error(n.EMPTY_PATH);
  return r;
}
export {
  m as getPointer
};
