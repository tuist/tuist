import { defineComponent as r, openBlock as n, createElementBlock as a, mergeProps as m, unref as u, renderSlot as s, createElementVNode as t, createCommentVNode as f } from "vue";
import { useBindCx as p } from "../../hooks/useBindCx.js";
const x = /* @__PURE__ */ r({
  inheritAttrs: !1,
  __name: "ScalarSearchResultList",
  props: {
    noResults: { type: Boolean }
  },
  setup(c) {
    const { cx: l } = p();
    return (e, o) => (n(), a("ul", m({ role: "listbox" }, u(l)("flex flex-col")), [
      e.noResults ? s(e.$slots, "noResults", { key: 0 }, () => [
        o[0] || (o[0] = t("div", { class: "flex flex-col items-center gap-2 px-3 py-4" }, [
          t("div", { class: "rotate-90 text-lg font-bold" }, ":("),
          t("div", { class: "text-sm font-medium text-c-2" }, "No results found")
        ], -1))
      ]) : f("", !0),
      s(e.$slots, "default")
    ], 16));
  }
});
export {
  x as default
};
