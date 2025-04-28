import { defineComponent as f, ref as l, onMounted as p, openBlock as d, createBlock as h, resolveDynamicComponent as u, withCtx as m, renderSlot as g } from "vue";
import { useIntersectionObserver as v } from "@vueuse/core";
const x = /* @__PURE__ */ f({
  __name: "IntersectionObserver",
  props: {
    id: {},
    is: {}
  },
  emits: ["intersecting"],
  setup(o, { emit: r }) {
    const i = o, s = r, n = l(), c = (e) => {
      const t = e.offsetHeight;
      return `${t / 2}px 0px ${t / 2}px 0px`;
    }, a = (e) => e.offsetHeight < window.innerHeight ? 0.8 : 0.5;
    return p(() => {
      if (n.value) {
        const e = {
          rootMargin: c(n.value),
          threshold: a(n.value)
        };
        v(
          n,
          ([{ isIntersecting: t }]) => {
            t && i.id && s("intersecting");
          },
          e
        );
      }
    }), (e, t) => (d(), h(u(e.is ?? "div"), {
      id: e.id,
      ref_key: "intersectionObserverRef",
      ref: n
    }, {
      default: m(() => [
        g(e.$slots, "default")
      ]),
      _: 3
    }, 8, ["id"]));
  }
});
export {
  x as default
};
