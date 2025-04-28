import { defineComponent as t, openBlock as a, createElementBlock as i, createVNode as l, unref as n, createElementVNode as r, toDisplayString as p, renderSlot as d } from "vue";
import { ScalarIconButton as c } from "@scalar/components";
import { useSidebar as m } from "../hooks/useSidebar.js";
const u = { class: "references-mobile-header t-doc__header" }, b = { class: "references-mobile-breadcrumbs" }, f = { class: "references-mobile-header-actions" }, M = /* @__PURE__ */ t({
  __name: "MobileHeader",
  props: {
    open: { type: Boolean }
  },
  emits: ["update:open"],
  setup(_) {
    const { breadcrumb: s } = m();
    return (e, o) => (a(), i("div", u, [
      l(n(c), {
        icon: e.open ? "Close" : "Menu",
        label: e.open ? "Close Menu" : "Open Menu",
        size: "md",
        onClick: o[0] || (o[0] = (h) => e.$emit("update:open", !e.open))
      }, null, 8, ["icon", "label"]),
      r("span", b, p(n(s)), 1),
      r("div", f, [
        d(e.$slots, "actions", {}, void 0, !0)
      ])
    ]));
  }
});
export {
  M as default
};
