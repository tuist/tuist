import { defineComponent as p, openBlock as i, createBlock as f, unref as e, withCtx as t, createVNode as r, mergeProps as n, renderSlot as s } from "vue";
import { Menu as u, MenuItems as _, MenuButton as c } from "@headlessui/vue";
import { useBindCx as d } from "../../hooks/useBindCx.js";
import B from "./ScalarDropdownMenu.vue.js";
import h from "../ScalarFloating/ScalarFloating.vue.js";
const $ = {}, x = /* @__PURE__ */ p({
  ...$,
  inheritAttrs: !1,
  __name: "ScalarDropdown",
  props: {
    placement: {},
    offset: {},
    resize: { type: Boolean },
    target: {},
    middleware: {},
    teleport: { type: [Boolean, String] }
  },
  setup(g) {
    const { cx: l } = d();
    return (o, y) => (i(), f(e(u), null, {
      default: t(({ open: a }) => [
        r(e(h), n(o.$props, {
          placement: o.placement ?? "bottom-start"
        }), {
          floating: t(({ width: m }) => [
            r(B, n({
              is: e(_),
              style: { width: m }
            }, e(l)("max-h-[inherit]")), {
              default: t(() => [
                s(o.$slots, "items", { open: a })
              ]),
              _: 2
            }, 1040, ["is", "style"])
          ]),
          default: t(() => [
            r(e(c), { as: "template" }, {
              default: t(() => [
                s(o.$slots, "default", { open: a })
              ]),
              _: 2
            }, 1024)
          ]),
          _: 2
        }, 1040, ["placement"])
      ]),
      _: 3
    }));
  }
});
export {
  x as default
};
