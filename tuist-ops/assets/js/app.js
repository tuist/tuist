import "noora/noora.css";
import "../css/app.css";
import Noora from "noora";

// tuist-ops renders dead views (no LiveSocket), so Noora's zag-js hooks
// aren't mounted by a LiveView lifecycle. Mount them ourselves: walk the
// elements that declare a phx-hook and call the matching definition's
// mounted() with no-op push shims standing in for the LiveView client.
const Hooks = (Noora && Noora.Hooks) || Noora || {};
const noop = () => {};

function mountNooraHooks() {
  for (const el of document.querySelectorAll("[phx-hook]")) {
    const def = Hooks[el.getAttribute("phx-hook")];
    if (def && typeof def.mounted === "function") {
      const view = Object.assign(Object.create(def), {
        el,
        pushEvent: noop,
        pushEventTo: noop,
        handleEvent: noop,
      });
      try {
        view.mounted();
      } catch (e) {
        console.error("noora hook failed", el, e);
      }
    }
  }
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", mountNooraHooks);
} else {
  mountNooraHooks();
}
