import { defineComponent as n, openBlock as a, createBlock as s, resolveDynamicComponent as i, mergeProps as u, unref as t, withCtx as p, renderSlot as c } from "vue";
import { cva as l } from "../../cva.js";
import { useBindCx as d } from "../../hooks/useBindCx.js";
const f = {}, y = /* @__PURE__ */ n({
  ...f,
  inheritAttrs: !1,
  __name: "ScalarHeaderButton",
  props: {
    is: { default: "button" },
    active: { type: Boolean }
  },
  setup(m) {
    const o = l({
      base: "group/button flex items-center rounded  px-2.5 py-1.5 font-medium no-underline leading-3 ",
      variants: {
        active: {
          true: "bg-b-3 cursor-default",
          false: "bg-transparent hover:bg-b-3 cursor-pointer"
        }
      }
    }), { cx: r } = d();
    return (e, b) => (a(), s(i(e.is), u({
      type: e.is === "button" ? "button" : void 0
    }, t(r)(t(o)({ active: e.active }))), {
      default: p(() => [
        c(e.$slots, "default")
      ]),
      _: 3
    }, 16, ["type"]));
  }
});
export {
  y as default
};
