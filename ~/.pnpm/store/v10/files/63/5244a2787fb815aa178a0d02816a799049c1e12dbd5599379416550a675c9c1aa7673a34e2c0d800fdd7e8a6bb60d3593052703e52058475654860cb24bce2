import { isJsonString as d } from "@scalar/oas-utils/helpers";
import { useEventBus as m } from "@vueuse/core";
const p = Symbol("downloadSpec"), u = m(p);
function b(o, n) {
  const t = d(o), s = t ? new Blob([o], { type: "application/json" }) : new Blob([o], { type: "application/x-yaml" }), c = URL.createObjectURL(s), l = t ? ".json" : ".yaml", a = "spec" + l, i = n ? n + l : a, e = document.createElement("a");
  e.href = c, e.download = i, e.dispatchEvent(
    new MouseEvent("click", {
      bubbles: !0,
      cancelable: !0,
      view: window
    })
  ), setTimeout(() => {
    window.URL.revokeObjectURL(c), e.remove();
  }, 100);
}
export {
  u as downloadSpecBus,
  b as downloadSpecFile
};
