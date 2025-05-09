import { defineComponent as r, openBlock as t, createElementBlock as n, renderSlot as o } from "vue";
const s = {
  key: 0,
  class: "screenreader-only"
}, d = /* @__PURE__ */ r({
  __name: "ScreenReader",
  props: {
    if: { type: Boolean, default: !0 }
  },
  setup(a) {
    return (e, l) => e.$props.if ? (t(), n("span", s, [
      o(e.$slots, "default", {}, void 0, !0)
    ])) : o(e.$slots, "default", { key: 1 }, void 0, !0);
  }
});
export {
  d as default
};
