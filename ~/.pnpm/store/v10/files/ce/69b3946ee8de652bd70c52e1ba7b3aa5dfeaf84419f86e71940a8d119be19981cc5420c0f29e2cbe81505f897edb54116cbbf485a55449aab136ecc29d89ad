import { defineComponent as t, openBlock as i, createElementBlock as n, mergeProps as r, unref as s, createVNode as l, createElementVNode as d, toDisplayString as c } from "vue";
import { cva as p } from "../../cva.js";
import { useBindCx as u } from "../../hooks/useBindCx.js";
import { styles as m } from "../ScalarButton/variants.js";
import f from "../ScalarIcon/ScalarIcon.vue.js";
const b = ["ariaDisabled"], h = { class: "sr-only" }, w = /* @__PURE__ */ t({
  inheritAttrs: !1,
  __name: "ScalarIconButton",
  props: {
    label: {},
    icon: {},
    disabled: { type: Boolean },
    variant: { default: "ghost" },
    size: { default: "md" },
    thickness: {}
  },
  setup(v) {
    const { cx: o } = u(), a = p({
      base: "scalar-icon-button grid aspect-square cursor-pointer rounded",
      variants: {
        size: {
          xxs: "size-3.5 p-0.5",
          xs: "size-5 p-1",
          sm: "size-6 p-1",
          md: "size-10 p-3",
          full: "h-full w-full"
        },
        disabled: {
          true: "cursor-not-allowed shadow-none"
        },
        variant: m
      }
    });
    return (e, z) => (i(), n("button", r({
      ariaDisabled: e.disabled || void 0,
      type: "button"
    }, s(o)(s(a)({ size: e.size, variant: e.variant, disabled: e.disabled }))), [
      l(s(f), {
        icon: e.icon,
        thickness: e.thickness
      }, null, 8, ["icon", "thickness"]),
      d("span", h, c(e.label), 1)
    ], 16, b));
  }
});
export {
  w as default
};
