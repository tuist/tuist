import { defineComponent as f, openBlock as a, createElementBlock as i, mergeProps as m, unref as o, normalizeClass as r, renderSlot as l, createCommentVNode as u, createVNode as g } from "vue";
import { useBindCx as b } from "../../hooks/useBindCx.js";
import { variants as v } from "./variants.js";
import y from "../ScalarLoading/ScalarLoading.vue.js";
const h = ["ariaDisabled", "type"], c = {
  key: 3,
  class: "centered-x absolute"
}, $ = /* @__PURE__ */ f({
  inheritAttrs: !1,
  __name: "ScalarButton",
  props: {
    disabled: { type: Boolean },
    fullWidth: { type: Boolean, default: !1 },
    loading: {},
    size: { default: "md" },
    variant: { default: "solid" },
    type: { default: "button" }
  },
  setup(k) {
    const { cx: p } = b();
    return (e, B) => {
      var s, n, t, d;
      return a(), i("button", m(
        {
          ariaDisabled: e.disabled || void 0,
          type: e.type
        },
        o(p)(o(v)({ fullWidth: e.fullWidth, disabled: e.disabled, size: e.size, variant: e.variant }), {
          relative: (s = e.loading) == null ? void 0 : s.isLoading
        })
      ), [
        e.$slots.icon ? (a(), i("div", {
          key: 0,
          class: r(["mr-2 h-4 w-4", { invisible: (n = e.loading) == null ? void 0 : n.isLoading }])
        }, [
          l(e.$slots, "icon")
        ], 2)) : u("", !0),
        e.loading ? (a(), i("span", {
          key: 1,
          class: r({ invisible: (t = e.loading) == null ? void 0 : t.isLoading })
        }, [
          l(e.$slots, "default")
        ], 2)) : l(e.$slots, "default", { key: 2 }),
        (d = e.loading) != null && d.isLoading ? (a(), i("div", c, [
          g(o(y), {
            loadingState: e.loading,
            size: "xs"
          }, null, 8, ["loadingState"])
        ])) : u("", !0)
      ], 16, h);
    };
  }
});
export {
  $ as default
};
