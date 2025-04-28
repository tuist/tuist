import { defineComponent as n, openBlock as o, createElementBlock as a, normalizeProps as i, guardReactiveProps as c, unref as d, createElementVNode as t, renderSlot as s } from "vue";
import { useBindCx as l } from "../../hooks/useBindCx.js";
const m = { class: "justify-start" }, f = { class: "justify-center" }, _ = { class: "justify-end" }, p = {}, g = /* @__PURE__ */ n({
  ...p,
  __name: "ScalarHeader",
  setup(u) {
    const { cx: r } = l();
    return (e, h) => (o(), a("header", i(c(
      d(r)(
        "flex min-h-header items-center justify-between gap-2 bg-b-2 border-b px-2 text-sm min-w-min",
        "*:flex *:flex-1 *:items-center *:gap-px"
      )
    )), [
      t("div", m, [
        s(e.$slots, "start")
      ]),
      t("div", f, [
        s(e.$slots, "default")
      ]),
      t("div", _, [
        s(e.$slots, "end")
      ])
    ], 16));
  }
});
export {
  g as default
};
