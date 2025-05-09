import { defineComponent as a, openBlock as l, createBlock as i, unref as n, withCtx as t, createVNode as s, renderSlot as p } from "vue";
import { MenuItem as m } from "@headlessui/vue";
import u from "./ScalarDropdownButton.vue.js";
const f = {}, B = /* @__PURE__ */ a({
  ...f,
  __name: "ScalarDropdownItem",
  props: {
    disabled: { type: Boolean }
  },
  emits: ["click"],
  setup(c) {
    return (e, o) => (l(), i(n(m), { disabled: e.disabled }, {
      default: t(({ active: d }) => [
        s(u, {
          active: d,
          disabled: e.disabled,
          onClick: o[0] || (o[0] = (r) => e.$emit("click", r))
        }, {
          default: t(() => [
            p(e.$slots, "default", {}, void 0, !0)
          ]),
          _: 2
        }, 1032, ["active", "disabled"])
      ]),
      _: 3
    }, 8, ["disabled"]));
  }
});
export {
  B as default
};
