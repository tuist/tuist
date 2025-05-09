import { defineComponent as u, openBlock as t, createElementBlock as l, normalizeClass as o, unref as n, createElementVNode as m, toDisplayString as p, createCommentVNode as b } from "vue";
import { cva as f, cx as h } from "../../cva.js";
const V = ["aria-checked", "aria-disabled"], g = {
  key: 0,
  class: "sr-only"
}, w = /* @__PURE__ */ u({
  __name: "ScalarToggle",
  props: {
    modelValue: { type: Boolean },
    disabled: { type: Boolean },
    label: {}
  },
  emits: ["update:modelValue"],
  setup(r, { emit: s }) {
    const a = r, d = s;
    function i() {
      a.disabled || d("update:modelValue", !a.modelValue);
    }
    const c = f({
      base: "relative h-3.5 w-6 cursor-pointer rounded-full bg-b-3 transition-colors duration-300",
      variants: {
        checked: { true: "bg-c-accent" },
        disabled: { true: "cursor-not-allowed opacity-40" }
      }
    });
    return (e, k) => (t(), l("button", {
      "aria-checked": e.modelValue,
      "aria-disabled": e.disabled,
      class: o(n(h)(n(c)({ checked: e.modelValue, disabled: e.disabled }))),
      role: "switch",
      type: "button",
      onClick: i
    }, [
      m("div", {
        class: o(["absolute left-px top-px flex h-3 w-3 items-center justify-center rounded-full bg-white text-c-accent transition-transform duration-300", { "translate-x-2.5": e.modelValue }])
      }, null, 2),
      e.label ? (t(), l("span", g, p(e.label), 1)) : b("", !0)
    ], 10, V));
  }
});
export {
  w as default
};
