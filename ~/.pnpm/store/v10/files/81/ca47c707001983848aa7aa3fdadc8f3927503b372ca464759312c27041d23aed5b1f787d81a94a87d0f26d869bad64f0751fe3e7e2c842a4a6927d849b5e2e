import { defineComponent as n, openBlock as a, createBlock as r, resolveDynamicComponent as s, normalizeClass as i, unref as t, withCtx as l, renderSlot as c } from "vue";
import { cva as d, cx as p } from "../../cva.js";
const u = {}, _ = /* @__PURE__ */ n({
  ...u,
  __name: "ScalarDropdownButton",
  props: {
    is: { default: "button" },
    active: { type: Boolean },
    disabled: { type: Boolean }
  },
  setup(m) {
    const o = d({
      base: [
        // Layout
        "flex h-8 min-w-0 items-center gap-1.5 rounded px-2.5 py-1.5 text-left",
        // Text / background style
        "truncate  no-underline text-sm text-c-1",
        // Interaction
        "cursor-pointer hover:bg-b-2 hover:text-c-1"
      ],
      variants: {
        disabled: { true: "pointer-events-none text-c-3" },
        active: { true: "bg-b-2 text-c-1" }
      }
    });
    return (e, v) => (a(), r(s(e.is), {
      class: i(["item", t(p)("scalar-dropdown-item", t(o)({ active: e.active, disabled: e.disabled }))]),
      type: e.is === "button" ? "button" : void 0
    }, {
      default: l(() => [
        c(e.$slots, "default", {}, void 0, !0)
      ]),
      _: 3
    }, 8, ["class", "type"]));
  }
});
export {
  _ as default
};
