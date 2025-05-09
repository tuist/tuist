import { defineComponent as n, openBlock as l, createBlock as a, resolveDynamicComponent as c, mergeProps as i, unref as o, withCtx as d, createElementVNode as t, renderSlot as r, createVNode as m } from "vue";
import { useBindCx as f } from "../../hooks/useBindCx.js";
import p from "../ScalarFloating/ScalarFloatingBackdrop.vue.js";
const _ = { class: "custom-scroll min-h-0 flex-1" }, u = { class: "flex flex-col p-0.75" }, x = {}, B = /* @__PURE__ */ n({
  ...x,
  inheritAttrs: !1,
  __name: "ScalarDropdownMenu",
  props: {
    is: {}
  },
  setup(h) {
    const { cx: s } = f();
    return (e, v) => (l(), a(c(e.is ?? "div"), i({
      role: "menu",
      tabindex: "0"
    }, o(s)("relative flex w-56")), {
      default: d(() => [
        t("div", _, [
          t("div", u, [
            r(e.$slots, "default")
          ]),
          r(e.$slots, "backdrop", {}, () => [
            m(o(p))
          ])
        ])
      ]),
      _: 3
    }, 16));
  }
});
export {
  B as default
};
