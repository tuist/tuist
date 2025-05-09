import { defineComponent as n, openBlock as s, createBlock as a, unref as r, mergeProps as i, withCtx as c, renderSlot as l } from "vue";
import { cva as p } from "../../cva.js";
import { useBindCx as d } from "../../hooks/useBindCx.js";
import f from "./ScalarMenuLink.vue.js";
const h = /* @__PURE__ */ n({
  inheritAttrs: !1,
  __name: "ScalarMenuProduct",
  props: {
    is: { default: "a" },
    selected: { type: Boolean },
    icon: {}
  },
  setup(m) {
    const { cx: o } = d(), t = p({
      base: "gap-1.5",
      variants: {
        selected: {
          true: "pointer-events-none bg-b-2 dark:bg-b-3",
          false: "cursor-pointer hover:bg-b-2 dark:hover:bg-b-3"
        }
      }
    });
    return (e, u) => (s(), a(r(f), i({
      is: e.is,
      icon: e.icon,
      strong: "",
      target: "_blank"
    }, r(o)(r(t)({ selected: e.selected }))), {
      default: c(() => [
        l(e.$slots, "default")
      ]),
      _: 3
    }, 16, ["is", "icon"]));
  }
});
export {
  h as default
};
