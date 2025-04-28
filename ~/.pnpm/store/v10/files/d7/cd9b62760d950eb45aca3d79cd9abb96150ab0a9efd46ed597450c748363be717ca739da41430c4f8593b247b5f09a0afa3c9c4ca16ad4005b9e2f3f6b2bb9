import { defineComponent as c, ref as a, onErrorCaptured as m, renderSlot as p, openBlock as l, createElementBlock as d, createElementVNode as i, toDisplayString as u, createCommentVNode as _ } from "vue";
const f = {
  key: 1,
  class: "rounded border bg-b-2 p-3 text-sm"
}, v = {
  key: 0,
  class: "mt-2 rounded border bg-b-1 p-2 font-code text-c-2"
}, E = /* @__PURE__ */ c({
  __name: "ScalarErrorBoundary",
  setup(b) {
    const n = a(!1), e = a();
    return m((r, t, o) => (console.error("[ERROR]", r, o), n.value = !0, e.value = r, !1)), (r, t) => {
      var o, s;
      return n.value ? (l(), d("div", f, [
        t[0] || (t[0] = i("div", { class: "p-2" }, "Oops, something went wrong here.", -1)),
        e.value ? (l(), d("div", v, u((o = e.value) == null ? void 0 : o.name) + ": " + u((s = e.value) == null ? void 0 : s.message), 1)) : _("", !0)
      ])) : p(r.$slots, "default", { key: 0 });
    };
  }
});
export {
  E as default
};
