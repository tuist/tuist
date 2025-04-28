import { defineComponent as n, openBlock as r, createElementBlock as t, normalizeProps as a, guardReactiveProps as i, unref as s, Fragment as c, createTextVNode as m, toDisplayString as l, createBlock as d, createCommentVNode as u } from "vue";
import { useBindCx as p } from "../../hooks/useBindCx.js";
import f from "../ScalarIcon/ScalarIcon.vue.js";
const b = ["src"], h = {
  key: 1,
  "aria-hidden": "true",
  class: "flex items-center justify-center text-3xs font-medium text-c-3 size-5 bg-b-3 rounded"
}, g = {
  key: 2,
  class: "flex-1 truncate"
}, z = /* @__PURE__ */ n({
  inheritAttrs: !1,
  __name: "ScalarMenuTeamProfile",
  props: {
    src: {},
    label: {}
  },
  setup(k) {
    const { cx: o } = p();
    return (e, y) => (r(), t("div", a(i(s(o)("flex h-full items-center gap-1"))), [
      e.src ? (r(), t("img", {
        key: 0,
        class: "size-5 rounded",
        role: "presentation",
        src: e.src
      }, null, 8, b)) : (r(), t("div", h, [
        e.label && e.label.length > 0 ? (r(), t(c, { key: 0 }, [
          m(l(e.label[0]), 1)
        ], 64)) : (r(), d(s(f), {
          key: 1,
          icon: "Users",
          size: "xs"
        }))
      ])),
      e.label && e.label.length > 0 ? (r(), t("div", g, l(e.label), 1)) : u("", !0)
    ], 16));
  }
});
export {
  z as default
};
