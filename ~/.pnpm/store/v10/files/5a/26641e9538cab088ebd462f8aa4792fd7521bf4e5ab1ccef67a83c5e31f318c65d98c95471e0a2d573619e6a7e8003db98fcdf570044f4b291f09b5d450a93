import { ref as t, watch as b, toValue as a, computed as l } from "vue";
function c(v, o = { enabled: t(!0) }) {
  const u = t(0), n = t(0), r = t();
  return typeof ResizeObserver < "u" && (r.value = new ResizeObserver(([e]) => {
    var i, d;
    e && (u.value = ((i = e.borderBoxSize[0]) == null ? void 0 : i.inlineSize) ?? 0, n.value = ((d = e.borderBoxSize[0]) == null ? void 0 : d.blockSize) ?? 0);
  })), b(
    [() => a(o.enabled), () => a(v)],
    ([e, i]) => {
      !i || !r.value || (e ? r.value.observe(i) : r.value.disconnect());
    },
    { immediate: !0 }
  ), {
    width: l(
      () => a(o.enabled) ? `${u.value}px` : void 0
    ),
    height: l(
      () => a(o.enabled) ? `${n.value}px` : void 0
    )
  };
}
export {
  c as useResizeWithTarget
};
