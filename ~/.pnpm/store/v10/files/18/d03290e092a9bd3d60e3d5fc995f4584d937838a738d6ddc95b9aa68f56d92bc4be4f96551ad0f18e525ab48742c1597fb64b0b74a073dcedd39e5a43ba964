import { defineComponent as n, useModel as s, openBlock as i, createElementBlock as u, mergeProps as a, unref as d, createElementVNode as t, normalizeClass as m, createVNode as f } from "vue";
import { useBindCx as p } from "../../hooks/useBindCx.js";
import c from "./ScalarColorModeToggleIcon.vue.js";
const g = ["aria-pressed"], x = {}, B = /* @__PURE__ */ n({
  ...x,
  inheritAttrs: !1,
  __name: "ScalarColorModeToggleButton",
  props: {
    modelValue: { type: Boolean },
    modelModifiers: {}
  },
  emits: ["update:modelValue"],
  setup(l) {
    const { cx: r } = p(), e = s(l, "modelValue");
    return (b, o) => (i(), u("button", a(
      {
        "aria-pressed": e.value,
        type: "button"
      },
      d(r)(
        "group/toggle flex h-6 w-[38px] brightness-lifted -mx-px items-center py-1.5 -my-1.5 relative outline-none"
      ),
      {
        onClick: o[0] || (o[0] = (v) => e.value = !e.value)
      }
    ), [
      o[1] || (o[1] = t("div", { class: "h-3 w-full bg-border mx-px rounded-xl group-focus-visible/toggle:outline -outline-offset-1" }, null, -1)),
      t("div", {
        class: m(["size-[23px] left-border absolute border rounded-full flex items-center justify-center bg-b-1 group-focus-visible/toggle:outline -outline-offset-1 transition-transform duration-300 ease-in-out", { "translate-x-[14px]": e.value }])
      }, [
        f(c, {
          is: "div",
          mode: e.value ? "dark" : "light"
        }, null, 8, ["mode"])
      ], 2)
    ], 16, g));
  }
});
export {
  B as default
};
