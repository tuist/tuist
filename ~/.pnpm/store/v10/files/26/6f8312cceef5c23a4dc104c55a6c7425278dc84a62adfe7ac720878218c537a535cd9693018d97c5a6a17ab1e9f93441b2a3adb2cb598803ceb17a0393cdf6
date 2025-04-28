import { defineComponent as d, openBlock as r, createBlock as i, unref as e, withCtx as t, createVNode as n, normalizeClass as f, renderSlot as a } from "vue";
import { ContextMenuRoot as u, ContextMenuTrigger as c, ContextMenuPortal as g, ContextMenuContent as C, ContextMenuItem as p } from "radix-vue";
const M = /* @__PURE__ */ d({
  __name: "ScalarContextMenu",
  props: {
    align: { default: "center" },
    side: { default: "bottom" },
    sideOffset: {},
    disabled: { type: Boolean, default: !1 },
    triggerClass: {}
  },
  setup(o) {
    const l = o;
    return (s, m) => (r(), i(e(u), null, {
      default: t(() => [
        n(e(c), {
          class: f(s.triggerClass),
          disabled: l.disabled
        }, {
          default: t(() => [
            a(s.$slots, "trigger")
          ]),
          _: 3
        }, 8, ["class", "disabled"]),
        n(e(g), null, {
          default: t(() => [
            n(e(C), {
              align: l.align,
              side: l.side,
              sideOffset: l.sideOffset
            }, {
              default: t(() => [
                n(e(p), null, {
                  default: t(() => [
                    a(s.$slots, "content")
                  ]),
                  _: 3
                })
              ]),
              _: 3
            }, 8, ["align", "side", "sideOffset"])
          ]),
          _: 3
        })
      ]),
      _: 3
    }));
  }
});
export {
  M as default
};
