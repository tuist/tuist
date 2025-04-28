import { defineComponent as l, openBlock as s, createBlock as p, unref as t, withCtx as c, createElementVNode as a, normalizeClass as n, createVNode as m, normalizeStyle as d, toDisplayString as u } from "vue";
import { ListboxOption as b } from "@headlessui/vue";
import { cva as f, cx as v } from "../../cva.js";
import y from "./ScalarListboxCheckbox.vue.js";
const C = /* @__PURE__ */ l({
  __name: "ScalarListboxItem",
  props: {
    option: {},
    style: {}
  },
  setup(g) {
    const r = f({
      base: [
        // Layout
        "group/item",
        "flex min-w-0 items-center gap-1.5 rounded px-2 py-1.5 text-left",
        // Text / background style
        "truncate bg-transparent text-c-1",
        // Interaction
        "cursor-pointer hover:bg-b-2"
      ],
      variants: {
        selected: { true: "text-c-1" },
        active: { true: "bg-b-2" },
        disabled: { true: "pointer-events-none opacity-50" }
      }
    });
    return (e, x) => (s(), p(t(b), {
      as: "template",
      disabled: e.option.disabled,
      value: e.option
    }, {
      default: c(({ active: i, selected: o }) => [
        a("li", {
          class: n(t(v)(t(r)({ active: i, selected: o, disabled: e.option.disabled })))
        }, [
          m(y, {
            selected: o,
            style: d(e.style)
          }, null, 8, ["selected", "style"]),
          a("span", {
            class: n(["inline-block min-w-0 flex-1 truncate", e.option.color ? e.option.color : "text-c-1"])
          }, u(e.option.label), 3)
        ], 2)
      ]),
      _: 1
    }, 8, ["disabled", "value"]));
  }
});
export {
  C as default
};
