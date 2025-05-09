import { defineComponent as m, openBlock as p, createBlock as d, withCtx as l, renderSlot as t, createVNode as s, createSlots as n } from "vue";
import f from "./ScalarComboboxOptions.vue.js";
import i from "./ScalarComboboxPopover.vue.js";
const c = /* @__PURE__ */ m({
  __name: "ScalarCombobox",
  props: {
    options: {},
    modelValue: {},
    placeholder: {},
    placement: {},
    offset: {},
    resize: { type: Boolean },
    target: {},
    middleware: {},
    teleport: { type: [Boolean, String] }
  },
  emits: ["update:modelValue"],
  setup(u) {
    return (e, V) => (p(), d(i, {
      middleware: e.middleware,
      offset: e.offset,
      placement: e.placement ?? "bottom-start",
      resize: e.resize,
      target: e.target,
      teleport: e.teleport
    }, {
      default: l(({ open: o }) => [
        t(e.$slots, "default", { open: o })
      ]),
      popover: l(({ open: o, close: a }) => [
        s(f, {
          modelValue: e.modelValue ? [e.modelValue] : [],
          open: o,
          options: e.options,
          placeholder: e.placeholder,
          "onUpdate:modelValue": (r) => (a(), e.$emit("update:modelValue", r[0]))
        }, n({ _: 2 }, [
          e.$slots.before ? {
            name: "before",
            fn: l(() => [
              t(e.$slots, "before", { open: o })
            ]),
            key: "0"
          } : void 0,
          e.$slots.after ? {
            name: "after",
            fn: l(() => [
              t(e.$slots, "after", { open: o })
            ]),
            key: "1"
          } : void 0
        ]), 1032, ["modelValue", "open", "options", "placeholder", "onUpdate:modelValue"])
      ]),
      _: 3
    }, 8, ["middleware", "offset", "placement", "resize", "target", "teleport"]));
  }
});
export {
  c as default
};
