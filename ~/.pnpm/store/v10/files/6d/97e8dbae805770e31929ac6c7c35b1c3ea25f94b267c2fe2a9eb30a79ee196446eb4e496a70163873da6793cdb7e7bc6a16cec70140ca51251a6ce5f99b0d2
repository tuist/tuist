import n from "whatwg-mimetype";
import { textMediaTypes as o } from "../../views/Request/consts/mediaTypes.js";
function m(r, t) {
  const e = new n(t);
  return o.includes(e.essence) ? new TextDecoder(e.parameters.get("charset")).decode(r) : new Blob([r], { type: e.essence });
}
export {
  m as decodeBuffer
};
