import { defineComponent as m, ref as r, openBlock as s, createElementBlock as p, Fragment as f, createVNode as n, renderSlot as _, nextTick as v } from "vue";
import d from "./DropEventListener.vue.js";
import I from "./ImportCollectionModal.vue.js";
/* empty css                           */
import y from "./PasteEventListener.vue.js";
import $ from "./UrlQueryParameterChecker.vue.js";
const C = /* @__PURE__ */ m({
  __name: "ImportCollectionListener",
  setup(g) {
    const e = r(null), t = r(null), o = r(null);
    async function u() {
      e.value = null, t.value = null, o.value = null, await v();
    }
    async function l(a, i = null, c) {
      await u(), e.value = a, t.value = i, o.value = c;
    }
    return (a, i) => (s(), p(f, null, [
      n(I, {
        eventType: o.value,
        integration: t.value,
        source: e.value,
        onImportFinished: u
      }, null, 8, ["eventType", "integration", "source"]),
      n(y, { onInput: l }),
      n(d, { onInput: l }),
      n($, { onInput: l }),
      _(a.$slots, "default")
    ], 64));
  }
});
export {
  C as default
};
