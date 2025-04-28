import { defineComponent as o, openBlock as r, createBlock as a, Teleport as s, unref as l, createElementVNode as d, mergeProps as n, renderSlot as p } from "vue";
import { useTeleport as i } from "./useTeleport.js";
const m = {}, b = /* @__PURE__ */ o({
  ...m,
  inheritAttrs: !1,
  __name: "ScalarTeleport",
  props: {
    to: {},
    immediate: { type: Boolean },
    disabled: { type: Boolean }
  },
  setup(f) {
    const t = i();
    return (e, c) => (r(), a(s, {
      defer: !e.immediate,
      disabled: e.disabled,
      to: e.to || l(t)
    }, [
      d("div", n({
        class: "scalar-app",
        style: { display: "contents" }
      }, e.$attrs), [
        p(e.$slots, "default")
      ], 16)
    ], 8, ["defer", "disabled", "to"]));
  }
});
export {
  b as default
};
