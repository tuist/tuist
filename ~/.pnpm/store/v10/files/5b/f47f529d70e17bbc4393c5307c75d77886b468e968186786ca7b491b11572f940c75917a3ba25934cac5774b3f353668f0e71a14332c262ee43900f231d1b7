import { defineComponent as h, computed as f, openBlock as i, createElementBlock as l, normalizeClass as y, Fragment as v, renderList as x, normalizeStyle as m, createElementVNode as $, toDisplayString as k } from "vue";
const p = 500, o = 100, B = /* @__PURE__ */ h({
  __name: "ScalarAsciiArt",
  props: {
    art: {},
    animate: { type: Boolean }
  },
  setup(u) {
    const d = u, n = f(() => d.art.split(`
`)), g = (a, s) => {
      var e, t, r, c;
      return {
        animationDuration: `${a * o}ms, ${p}ms`,
        animationTimingFunction: `steps(${a}), step-end`,
        animationDelay: `${s * o}ms, 0ms`,
        animationIterationCount: `1, ${((((e = n.value) == null ? void 0 : e.length) ?? 0) + (((c = (r = n.value) == null ? void 0 : r[((t = n.value) == null ? void 0 : t.length) - 1]) == null ? void 0 : c.length) ?? 0) + 5) * o / p}`
      };
    };
    return (a, s) => (i(), l("div", {
      class: y(["ascii-art font-code flex flex-col items-start text-[6px] leading-[7px]", { "ascii-art-animate": a.animate }])
    }, [
      (i(!0), l(v, null, x(n.value, (e, t) => (i(), l("span", {
        key: t,
        class: "inline-block",
        style: m({ width: `calc(${e.length + 1}ch)` })
      }, [
        $("span", {
          class: "inline-block whitespace-pre overflow-hidden",
          style: m(g(e.length, t))
        }, k(e), 5)
      ], 4))), 128))
    ], 2));
  }
});
export {
  B as default
};
