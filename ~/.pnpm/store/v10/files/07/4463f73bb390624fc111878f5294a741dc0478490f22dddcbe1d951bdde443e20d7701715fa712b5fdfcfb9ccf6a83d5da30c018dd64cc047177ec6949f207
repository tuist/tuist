import { defineComponent as d, ref as f, openBlock as p, createBlock as n, withCtx as l, createSlots as u, renderSlot as a, createCommentVNode as b } from "vue";
import $ from "./ScalarComboboxOptions.vue.js";
import V from "./ScalarComboboxPopover.vue.js";
const w = /* @__PURE__ */ d({
  __name: "ScalarComboboxMultiselect",
  props: {
    options: {},
    modelValue: {},
    placeholder: {},
    isDeletable: { type: Boolean },
    placement: {},
    offset: {},
    resize: { type: Boolean },
    target: {},
    middleware: {},
    teleport: { type: [Boolean, String] }
  },
  emits: ["update:modelValue", "delete"],
  setup(y, { expose: i }) {
    const s = f(null);
    return i({ comboboxPopoverRef: s }), (e, o) => (p(), n(V, {
      ref_key: "comboboxPopoverRef",
      ref: s,
      middleware: e.middleware,
      offset: e.offset,
      placement: e.placement ?? "bottom-start",
      resize: e.resize,
      target: e.target,
      teleport: e.teleport
    }, {
      popover: l(({ open: t }) => {
        var m;
        return [
          (m = e.options) != null && m.length ? (p(), n($, {
            key: 0,
            isDeletable: e.isDeletable,
            modelValue: e.modelValue,
            multiselect: "",
            open: t,
            options: e.options,
            placeholder: e.placeholder,
            onDelete: o[0] || (o[0] = (r) => e.$emit("delete", r)),
            "onUpdate:modelValue": o[1] || (o[1] = (r) => e.$emit("update:modelValue", r))
          }, u({ _: 2 }, [
            e.$slots.before ? {
              name: "before",
              fn: l(() => [
                a(e.$slots, "before", { open: t })
              ]),
              key: "0"
            } : void 0,
            e.$slots.after ? {
              name: "after",
              fn: l(() => [
                a(e.$slots, "after", { open: t })
              ]),
              key: "1"
            } : void 0
          ]), 1032, ["isDeletable", "modelValue", "open", "options", "placeholder"])) : b("", !0)
        ];
      }),
      default: l(() => [
        a(e.$slots, "default")
      ]),
      _: 3
    }, 8, ["middleware", "offset", "placement", "resize", "target", "teleport"]));
  }
});
export {
  w as default
};
