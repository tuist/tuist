import { defineComponent as l, useSlots as d, openBlock as u, createBlock as f, resolveDynamicComponent as g, mergeProps as c, createSlots as k, renderList as y, withCtx as C, renderSlot as D, normalizeProps as S, guardReactiveProps as $ } from "vue";
import M from "./ClassicLayout.vue.js";
import n from "./ModernLayout.vue.js";
const P = /* @__PURE__ */ l({
  __name: "Layouts",
  props: {
    configuration: {},
    parsedSpec: {},
    rawSpec: {},
    isDark: { type: Boolean }
  },
  emits: ["toggleDarkMode", "updateContent"],
  setup(s) {
    const a = s, p = d(), i = {
      modern: n,
      classic: M
    };
    return (o, e) => (u(), f(g(i[o.configuration.layout ?? "modern"] ?? n), c(a, {
      onToggleDarkMode: e[0] || (e[0] = (t) => o.$emit("toggleDarkMode")),
      onUpdateContent: e[1] || (e[1] = (t) => o.$emit("updateContent", t))
    }), k({ _: 2 }, [
      y(p, (t, r) => ({
        name: r,
        fn: C((m) => [
          D(o.$slots, r, S($(m || {})))
        ])
      }))
    ]), 1040));
  }
});
export {
  P as default
};
