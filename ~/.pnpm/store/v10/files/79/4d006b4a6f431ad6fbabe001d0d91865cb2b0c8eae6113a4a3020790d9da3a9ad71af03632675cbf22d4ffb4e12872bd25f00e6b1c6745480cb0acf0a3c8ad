import { defineComponent as l, openBlock as a, createElementBlock as i, normalizeProps as c, guardReactiveProps as d, unref as s, renderSlot as t, createElementVNode as r, createVNode as m } from "vue";
import { useBindCx as f } from "../../hooks/useBindCx.js";
import p from "../ScalarColorModeToggle/ScalarColorModeToggle.vue.js";
const _ = { class: "flex items-center" }, u = { class: "flex-1 min-w-0 flex items-center text-sm text-sidebar-c-2" }, x = {}, w = /* @__PURE__ */ l({
  ...x,
  inheritAttrs: !1,
  __name: "ScalarSidebarFooter",
  setup(b) {
    const { cx: n } = f();
    return (e, o) => (a(), i("div", c(d(s(n)("flex flex-col gap-3 p-3 border-t"))), [
      t(e.$slots, "default"),
      r("div", _, [
        r("div", u, [
          t(e.$slots, "description", {}, () => [
            o[0] || (o[0] = r("a", {
              class: "no-underline hover:underline",
              href: "https://www.scalar.com",
              target: "_blank"
            }, " Powered by Scalar ", -1))
          ])
        ]),
        t(e.$slots, "toggle", {}, () => [
          m(s(p))
        ])
      ])
    ], 16));
  }
});
export {
  w as default
};
