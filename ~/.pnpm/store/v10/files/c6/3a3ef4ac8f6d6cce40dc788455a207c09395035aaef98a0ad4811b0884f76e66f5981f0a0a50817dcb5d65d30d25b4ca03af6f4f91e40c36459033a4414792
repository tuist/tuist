import { defineComponent as r, openBlock as o, createBlock as n, unref as s, withCtx as a, normalizeClass as t, createElementBlock as i, createElementVNode as l, renderSlot as c } from "vue";
import { DropdownMenu as m } from "radix-vue/namespaced";
import f from "../ScalarDropdown/ScalarDropdownButton.vue.js";
import p from "../ScalarIcon/ScalarIcon.vue.js";
const d = {
  key: 1,
  class: "size-3"
}, _ = /* @__PURE__ */ r({
  __name: "ScalarMenuLink",
  props: {
    is: { default: () => m.Item },
    icon: {},
    strong: { type: Boolean }
  },
  setup(u) {
    return (e, k) => (o(), n(s(f), {
      is: e.is,
      as: "a"
    }, {
      default: a(() => [
        e.icon ? (o(), n(s(p), {
          key: 0,
          class: t(e.strong ? "text-c-1" : "text-c-2"),
          icon: e.icon,
          size: "xs",
          thickness: e.strong ? "2.5" : "2"
        }, null, 8, ["class", "icon", "thickness"])) : (o(), i("div", d)),
        l("div", {
          class: t(["flex items-center flex-1", e.strong ? "font-medium" : "font-normal"])
        }, [
          c(e.$slots, "default")
        ], 2)
      ]),
      _: 3
    }, 8, ["is"]));
  }
});
export {
  _ as default
};
