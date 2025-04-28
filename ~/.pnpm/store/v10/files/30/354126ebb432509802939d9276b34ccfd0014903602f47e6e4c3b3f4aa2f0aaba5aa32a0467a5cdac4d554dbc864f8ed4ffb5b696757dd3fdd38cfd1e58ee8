import { defineComponent as b, ref as o, computed as t, onMounted as w, onBeforeUnmount as E, watchEffect as k, openBlock as v, createElementBlock as f, normalizeClass as h, createElementVNode as _, normalizeStyle as m, Fragment as $, renderList as z, toDisplayString as L } from "vue";
const B = /* @__PURE__ */ b({
  __name: "ScalarVirtualText",
  props: {
    text: {},
    lineHeight: { default: 20 },
    containerClass: { default: "" },
    contentClass: { default: "" },
    lineClass: { default: "" }
  },
  setup(p) {
    const e = p, n = o(null), s = o(null), r = o(0), d = o(0), l = t(() => e.text.split(`
`)), x = t(() => l.value.length * e.lineHeight), a = t(
      () => Math.floor(r.value / e.lineHeight)
    ), H = t(
      () => Math.min(
        Math.ceil(
          (r.value + d.value) / e.lineHeight
        ),
        l.value.length
      )
    ), y = t(() => {
      const g = Math.max(0, a.value - 10), u = Math.min(l.value.length, H.value + 10);
      return l.value.slice(g, u);
    }), C = t(() => ({
      height: `${x.value}px`,
      transform: `translateY(${Math.max(0, a.value - 10) * e.lineHeight}px)`
    })), M = () => n.value && (r.value = n.value.scrollTop), c = () => n.value && (d.value = n.value.clientHeight);
    return w(() => {
      c(), window.addEventListener("resize", c);
    }), E(() => {
      window.removeEventListener("resize", c);
    }), k(() => {
      s.value && (s.value.style.transform = `translateY(${Math.max(0, a.value - 10) * e.lineHeight}px)`);
    }), (i, g) => (v(), f("div", {
      ref_key: "containerRef",
      ref: n,
      class: h(["scalar-virtual-text overflow-auto", i.containerClass]),
      onScroll: M
    }, [
      _("code", {
        ref_key: "contentRef",
        ref: s,
        class: h(["scalar-virtual-text-content", i.contentClass]),
        style: m(C.value)
      }, [
        (v(!0), f($, null, z(y.value, (u, S) => (v(), f("div", {
          key: a.value + S,
          class: h(["scalar-virtual-text-line", i.lineClass]),
          style: m({
            height: `${e.lineHeight}px`,
            lineHeight: `${e.lineHeight}px`
          })
        }, L(u), 7))), 128))
      ], 6)
    ], 34));
  }
});
export {
  B as default
};
