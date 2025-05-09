import { defineComponent as p, openBlock as m, createElementBlock as c, normalizeProps as u, guardReactiveProps as h, unref as C, createVNode as r, withCtx as t, createTextVNode as l } from "vue";
import { useBindCx as k } from "../../hooks/useBindCx.js";
import d from "./ScalarMenuProduct.vue.js";
const g = /* @__PURE__ */ p({
  inheritAttrs: !1,
  __name: "ScalarMenuProducts",
  props: {
    selected: {},
    hrefs: {}
  },
  emits: ["open"],
  setup(b) {
    const { cx: f } = k();
    return (o, e) => {
      var n, i, a;
      return m(), c("div", u(h(C(f)("flex flex-col"))), [
        r(d, {
          href: ((n = o.hrefs) == null ? void 0 : n.dashboard) ?? "https://dashboard.scalar.com",
          icon: "House",
          selected: o.selected === "dashboard",
          onClick: e[0] || (e[0] = (s) => o.$emit("open", s, "dashboard"))
        }, {
          default: t(() => e[3] || (e[3] = [
            l(" Dashboard ")
          ])),
          _: 1
        }, 8, ["href", "selected"]),
        r(d, {
          href: ((i = o.hrefs) == null ? void 0 : i.docs) ?? "https://docs.scalar.com",
          icon: "Page",
          selected: o.selected === "docs",
          onClick: e[1] || (e[1] = (s) => o.$emit("open", s, "docs"))
        }, {
          default: t(() => e[4] || (e[4] = [
            l(" Docs ")
          ])),
          _: 1
        }, 8, ["href", "selected"]),
        r(d, {
          href: ((a = o.hrefs) == null ? void 0 : a.client) ?? "https://client.scalar.com",
          icon: "ExternalLink",
          selected: o.selected === "client",
          onClick: e[2] || (e[2] = (s) => o.$emit("open", s, "client"))
        }, {
          default: t(() => e[5] || (e[5] = [
            l(" Client ")
          ])),
          _: 1
        }, 8, ["href", "selected"])
      ], 16);
    };
  }
});
export {
  g as default
};
