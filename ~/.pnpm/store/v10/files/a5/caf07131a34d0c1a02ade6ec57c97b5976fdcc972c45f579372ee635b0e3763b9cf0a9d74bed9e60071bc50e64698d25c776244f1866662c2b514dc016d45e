import { defineComponent as a, openBlock as s, createBlock as p, resolveDynamicComponent as i, mergeProps as l, unref as o, withCtx as u, renderSlot as n, createVNode as d, createElementVNode as f, createTextVNode as c, toDisplayString as m } from "vue";
import { cva as v } from "../../cva.js";
import { useBindCx as h } from "../../hooks/useBindCx.js";
import y from "../ScalarIcon/ScalarIcon.vue.js";
const C = { class: "sr-only" }, _ = {}, k = /* @__PURE__ */ a({
  ..._,
  inheritAttrs: !1,
  __name: "ScalarSidebarGroupToggle",
  props: {
    is: { default: "div" },
    open: { type: Boolean, default: !1 },
    icon: { default: "ChevronRight" }
  },
  setup(b) {
    const t = v({
      base: "size-4 -m-px transition-transform duration-100",
      variants: { open: { true: "rotate-90" } },
      defaultVariants: { open: !1 }
    }), { cx: r } = h();
    return (e, g) => (s(), p(i(e.is), l({
      type: e.is === "button" ? "button" : void 0
    }, o(r)(o(t)({ open: e.open }))), {
      default: u(() => [
        n(e.$slots, "default", { open: e.open }, () => [
          d(o(y), { icon: e.icon }, null, 8, ["icon"])
        ]),
        f("span", C, [
          n(e.$slots, "label", { open: e.open }, () => [
            c(m(e.open ? "Close" : "Open") + " Group ", 1)
          ])
        ])
      ]),
      _: 3
    }, 16, ["type"]));
  }
});
export {
  k as default
};
