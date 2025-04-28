import { defineComponent as d, computed as m, openBlock as e, createElementBlock as t, normalizeClass as h, Fragment as o, renderList as u, toDisplayString as r, createTextVNode as _ } from "vue";
const k = { key: 0 }, B = /* @__PURE__ */ d({
  __name: "OperationPath",
  props: {
    path: {},
    deprecated: { type: Boolean }
  },
  setup(s) {
    const p = s, c = (a) => a.startsWith("{") && a.endsWith("}"), i = m(() => p.path.split(/({[^}]+})/));
    return (a, y) => (e(), t("span", {
      class: h(["operation-path", { deprecated: a.deprecated }])
    }, [
      (e(!0), t(o, null, u(i.value, (n, l) => (e(), t(o, { key: l }, [
        c(n) ? (e(), t("em", k, r(n), 1)) : (e(), t(o, { key: 1 }, [
          _(r(n), 1)
        ], 64))
      ], 64))), 128))
    ], 2));
  }
});
export {
  B as default
};
