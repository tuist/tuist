import { defineComponent as u, openBlock as r, createElementBlock as d, createElementVNode as o, normalizeClass as l, withModifiers as n } from "vue";
const a = { class: "text-c-3 flex -my-1 justify-center rounded text-xxs p-0.5 gap-0.5" }, i = /* @__PURE__ */ u({
  __name: "ResponseBodyToggle",
  props: {
    modelValue: { type: Boolean }
  },
  emits: ["update:modelValue"],
  setup(p) {
    return (e, t) => (r(), d("div", a, [
      o("button", {
        class: l(["hover:bg-b-3 rounded px-1", { "bg-b-3 text-c-1 cursor-default": e.modelValue }]),
        type: "button",
        onClick: t[0] || (t[0] = n((s) => e.$emit("update:modelValue", !0), ["stop"]))
      }, " Preview ", 2),
      o("button", {
        class: l(["hover:bg-b-3 rounded px-1", { "bg-b-3 text-c-1 cursor-default": !e.modelValue }]),
        type: "button",
        onClick: t[1] || (t[1] = n((s) => e.$emit("update:modelValue", !1), ["stop"]))
      }, " Raw ", 2)
    ]));
  }
});
export {
  i as default
};
