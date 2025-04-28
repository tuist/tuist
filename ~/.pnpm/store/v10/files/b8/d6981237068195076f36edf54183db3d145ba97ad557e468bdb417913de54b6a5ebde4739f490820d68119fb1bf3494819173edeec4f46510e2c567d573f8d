import { defineComponent as s, openBlock as d, createBlock as c, mergeProps as l, withCtx as n, createElementVNode as e, renderSlot as r } from "vue";
import p from "./CardContent.vue.js";
const i = { class: "scalar-card-header-slots" }, h = { class: "scalar-card-header-slot scalar-card-header-title" }, m = { class: "scalar-card-header-slot scalar-card-header-actions" }, B = /* @__PURE__ */ s({
  __name: "CardHeader",
  props: {
    muted: { type: Boolean },
    contrast: { type: Boolean },
    frameless: { type: Boolean },
    transparent: { type: Boolean },
    borderless: { type: Boolean }
  },
  setup(t) {
    const o = t;
    return (a, _) => (d(), c(p, l(o, { class: "scalar-card-header" }), {
      default: n(() => [
        e("div", i, [
          e("div", h, [
            r(a.$slots, "default", {}, void 0, !0)
          ]),
          e("div", m, [
            r(a.$slots, "actions", {}, void 0, !0)
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
