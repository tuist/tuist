import { defineComponent as r, openBlock as n, createElementBlock as s, Fragment as l, renderSlot as a, createElementVNode as c, unref as p } from "vue";
import { useProvideTeleport as d } from "./useTeleport.js";
const i = ["id"], _ = {}, k = /* @__PURE__ */ r({
  ..._,
  inheritAttrs: !1,
  __name: "ScalarTeleportRoot",
  props: {
    id: {}
  },
  setup(e) {
    const t = d(e.id);
    return (o, u) => (n(), s(l, null, [
      a(o.$slots, "default"),
      c("div", {
        id: p(t),
        class: "scalar-teleport-root contents"
      }, null, 8, i)
    ], 64));
  }
});
export {
  k as default
};
