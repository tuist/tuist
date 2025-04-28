import { defineComponent as u, computed as r, openBlock as p, createBlock as i, resolveDynamicComponent as m, normalizeStyle as c, withCtx as d, renderSlot as v, normalizeProps as h, guardReactiveProps as f, createTextVNode as y, toDisplayString as b } from "vue";
import { requestMethodAbbreviations as C, requestMethodColors as z } from "./constants.js";
import { isRequestMethod as l } from "./utils/isRequestMethod.js";
const S = /* @__PURE__ */ u({
  __name: "HttpMethod",
  props: {
    as: {},
    property: {},
    short: { type: Boolean },
    method: {}
  },
  setup(s) {
    const n = s, e = r(() => n.method.trim().toUpperCase()), t = r(() => l(e.value) ? C[e.value] : e.value.slice(0, 4)), a = r(() => l(e.value) ? z[e.value] : "var(--scalar-color-ghost)");
    return (o, M) => (p(), i(m(o.as ?? "span"), {
      style: c({ [o.property || "color"]: a.value })
    }, {
      default: d(() => [
        v(o.$slots, "default", h(f({ normalized: e.value, abbreviated: t.value, color: a.value })), () => [
          y(b(o.short ? t.value : e.value), 1)
        ])
      ]),
      _: 3
    }, 8, ["style"]));
  }
});
export {
  S as default
};
