import { defineComponent as a, openBlock as l, createBlock as c, unref as e, withCtx as p, createElementVNode as n, renderSlot as t, createVNode as r, createTextVNode as i, toDisplayString as u } from "vue";
import m from "../ScalarHeader/ScalarHeaderButton.vue.js";
import s from "../ScalarIcon/ScalarIcon.vue.js";
const d = { class: "h-5 w-auto" }, _ = { class: "sr-only" }, B = /* @__PURE__ */ a({
  __name: "ScalarMenuButton",
  props: {
    open: { type: Boolean }
  },
  setup(f) {
    return (o, h) => (l(), c(e(m), { class: "gap-0.5 px-2" }, {
      default: p(() => [
        n("div", d, [
          t(o.$slots, "logo", {}, () => [
            r(e(s), { icon: "Logo" })
          ])
        ]),
        n("span", _, [
          t(o.$slots, "label", {}, () => [
            i(u(o.open ? "Close Menu" : "Open Menu"), 1)
          ])
        ]),
        r(e(s), {
          class: "shrink-0 text-c-3 group-hover/button:text-c-1",
          icon: o.open ? "ChevronUp" : "ChevronDown",
          size: "md"
        }, null, 8, ["icon"])
      ]),
      _: 3
    }));
  }
});
export {
  B as default
};
