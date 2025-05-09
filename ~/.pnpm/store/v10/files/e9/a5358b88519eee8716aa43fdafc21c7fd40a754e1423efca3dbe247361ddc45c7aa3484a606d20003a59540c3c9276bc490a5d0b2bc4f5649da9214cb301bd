import { defineComponent as a, openBlock as t, createElementBlock as o, normalizeClass as l, renderSlot as r, createTextVNode as p, createCommentVNode as n } from "vue";
const d = {
  key: 0,
  class: "property-detail-prefix"
}, i = {
  key: 1,
  class: "property-detail-value"
}, u = {
  key: 2,
  class: "property-detail-value"
}, m = /* @__PURE__ */ a({
  __name: "SchemaPropertyDetail",
  props: {
    truncate: { type: Boolean },
    code: { type: Boolean }
  },
  setup(c) {
    return (e, s) => (t(), o("span", {
      class: l(["property-detail", { "property-detail-truncate": e.truncate }])
    }, [
      e.$slots.prefix ? (t(), o("div", d, [
        r(e.$slots, "prefix", {}, void 0, !0),
        s[0] || (s[0] = p("  "))
      ])) : n("", !0),
      e.code ? (t(), o("code", i, [
        r(e.$slots, "default", {}, void 0, !0)
      ])) : (t(), o("span", u, [
        r(e.$slots, "default", {}, void 0, !0)
      ]))
    ], 2));
  }
});
export {
  m as default
};
