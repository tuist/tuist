import { defineComponent as n, ref as s, nextTick as i, renderSlot as u, createCommentVNode as r } from "vue";
import { lazyBus as a } from "./lazyBus.js";
const y = /* @__PURE__ */ n({
  __name: "Lazy",
  props: {
    id: {},
    isLazy: { type: Boolean, default: !0 },
    lazyTimeout: { default: 0 }
  },
  setup(d) {
    const e = d, l = (t = () => {
    }) => {
      typeof window > "u" || ("requestIdleCallback" in window ? setTimeout(() => window.requestIdleCallback(t), e.lazyTimeout) : setTimeout(() => i(t), e.lazyTimeout ?? 300));
    }, o = s(!e.isLazy);
    return e.isLazy ? l(() => {
      o.value = !0, e.id && i(() => a.emit({ id: e.id }));
    }) : e.id && i(() => a.emit({ id: e.id })), (t, f) => o.value ? u(t.$slots, "default", { key: 0 }) : r("", !0);
  }
});
export {
  y as default
};
