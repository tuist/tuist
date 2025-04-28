import { defineComponent as u, ref as c, openBlock as _, createBlock as v, unref as o, withCtx as t, createVNode as r, normalizeProps as y, guardReactiveProps as w, createSlots as x, renderSlot as l, mergeProps as B } from "vue";
import { Popover as P, PopoverButton as h, PopoverPanel as k } from "@headlessui/vue";
import { useBindCx as g } from "../../hooks/useBindCx.js";
import $ from "../ScalarFloating/ScalarFloating.vue.js";
import C from "../ScalarFloating/ScalarFloatingBackdrop.vue.js";
const z = /* @__PURE__ */ u({
  inheritAttrs: !1,
  __name: "ScalarComboboxPopover",
  props: {
    placement: {},
    offset: {},
    resize: { type: Boolean },
    target: {},
    middleware: {},
    teleport: { type: [Boolean, String] }
  },
  setup(S, { expose: s }) {
    const { cx: f } = g(), p = c(null), i = (e) => {
      var n;
      ["ArrowUp", "ArrowDown"].includes(e.key) && (e.preventDefault(), (n = e.target) == null || n.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" })));
    };
    return s({ popoverButtonRef: p }), (e, n) => (_(), v(o(P), { as: "template" }, {
      default: t(({ open: a }) => [
        r(o($), y(w(e.$props)), x({
          default: t(() => [
            r(o(h), {
              ref_key: "popoverButtonRef",
              ref: p,
              as: "template",
              onKeydown: i
            }, {
              default: t(() => [
                l(e.$slots, "default", { open: a })
              ]),
              _: 2
            }, 1536)
          ]),
          _: 2
        }, [
          a ? {
            name: "floating",
            fn: t(({ width: m }) => [
              r(o(k), B(
                {
                  focus: "",
                  style: { width: m }
                },
                o(f)("relative flex flex-col max-h-[inherit] w-40 rounded text-sm")
              ), {
                default: t(({ close: d }) => [
                  l(e.$slots, "popover", {
                    close: d,
                    open: a
                  }),
                  r(o(C))
                ]),
                _: 2
              }, 1040, ["style"])
            ]),
            key: "0"
          } : void 0
        ]), 1040)
      ]),
      _: 3
    }));
  }
});
export {
  z as default
};
