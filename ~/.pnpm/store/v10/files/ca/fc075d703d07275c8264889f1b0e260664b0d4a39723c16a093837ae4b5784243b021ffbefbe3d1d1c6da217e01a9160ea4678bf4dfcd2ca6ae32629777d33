import { defineComponent as i, ref as m, openBlock as u, createBlock as d, unref as l, withCtx as t, createVNode as n, renderSlot as e, createSlots as $, mergeProps as c } from "vue";
import { DropdownMenu as r } from "radix-vue/namespaced";
import _ from "./ScalarMenuButton.vue.js";
import g from "./ScalarMenuProducts.vue.js";
import v from "./ScalarMenuResources.vue.js";
import b from "../ScalarDropdown/ScalarDropdownMenu.vue.js";
const M = /* @__PURE__ */ i({
  inheritAttrs: !1,
  __name: "ScalarMenu",
  setup(k) {
    const s = m(!1);
    function a() {
      s.value = !1;
    }
    return (o, f) => (u(), d(l(r).Root, {
      open: s.value,
      "onUpdate:open": f[0] || (f[0] = (p) => s.value = p)
    }, {
      default: t(() => [
        n(l(r).Trigger, { asChild: "" }, {
          default: t(() => [
            e(o.$slots, "button", { open: s.value }, () => [
              n(_, {
                class: "min-w-0",
                open: s.value
              }, $({ _: 2 }, [
                o.$slots.logo ? {
                  name: "logo",
                  fn: t(() => [
                    e(o.$slots, "logo")
                  ]),
                  key: "0"
                } : void 0,
                o.$slots.label ? {
                  name: "label",
                  fn: t(() => [
                    e(o.$slots, "label")
                  ]),
                  key: "1"
                } : void 0
              ]), 1032, ["open"])
            ])
          ]),
          _: 3
        }),
        n(l(r).Content, c({
          align: "start",
          as: l(b),
          class: "max-h-radix-popper z-context",
          sideOffset: 5
        }, o.$attrs), {
          default: t(() => [
            e(o.$slots, "products", { close: a }, () => [
              n(g)
            ]),
            e(o.$slots, "profile", { close: a }),
            e(o.$slots, "sections", { close: a }, () => [
              n(v)
            ])
          ]),
          _: 3
        }, 16, ["as"])
      ]),
      _: 3
    }, 8, ["open"]));
  }
});
export {
  M as default
};
