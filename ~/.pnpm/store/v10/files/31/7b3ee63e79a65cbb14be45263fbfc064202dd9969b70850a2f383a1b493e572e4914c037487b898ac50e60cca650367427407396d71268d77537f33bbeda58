import { defineComponent as d, openBlock as o, createBlock as i, unref as t, withCtx as l, createVNode as s, normalizeClass as r, renderSlot as n, createCommentVNode as f } from "vue";
import { TooltipProvider as p, TooltipRoot as u, TooltipTrigger as m, TooltipContent as g } from "radix-vue";
import k from "../ScalarTeleport/ScalarTeleport.vue.js";
const T = /* @__PURE__ */ d({
  __name: "ScalarTooltip",
  props: {
    click: {},
    delay: {},
    skipDelay: { default: 1e3 },
    align: { default: "center" },
    side: { default: "top" },
    sideOffset: {},
    class: {},
    triggerClass: {},
    resize: { type: Boolean },
    as: {},
    disabled: { type: Boolean, default: !1 }
  },
  emits: ["click"],
  setup(c) {
    const e = c;
    return (a, y) => (o(), i(t(p), {
      delayDuration: e.delay,
      skipDelayDuration: e.skipDelay
    }, {
      default: l(() => [
        s(t(u), null, {
          default: l(() => [
            s(t(m), {
              as: e.as || "button",
              class: r(["flex items-center justify-center", [e.resize ? "w-full" : "", e.triggerClass]]),
              onClick: e.click
            }, {
              default: l(() => [
                n(a.$slots, "trigger")
              ]),
              _: 3
            }, 8, ["as", "class", "onClick"]),
            s(t(k), null, {
              default: l(() => [
                e.disabled ? f("", !0) : (o(), i(t(g), {
                  key: 0,
                  align: e.align,
                  class: r(["scalar-app z-context", e.class]),
                  side: e.side,
                  sideOffset: e.sideOffset
                }, {
                  default: l(() => [
                    n(a.$slots, "content")
                  ]),
                  _: 3
                }, 8, ["align", "class", "side", "sideOffset"]))
              ]),
              _: 3
            })
          ]),
          _: 3
        })
      ]),
      _: 3
    }, 8, ["delayDuration", "skipDelayDuration"]));
  }
});
export {
  T as default
};
