import { defineComponent as m, openBlock as t, createElementBlock as l, normalizeProps as h, mergeProps as p, unref as n, normalizeClass as o, createStaticVNode as g, createElementVNode as v, createCommentVNode as d, reactive as u } from "vue";
import { cva as c } from "../../cva.js";
import { useBindCx as f } from "../../hooks/useBindCx.js";
const z = {
  key: 0,
  class: "circular-loader"
};
function S() {
  return u({
    isValid: !1,
    isInvalid: !1,
    isLoading: !1,
    startLoading() {
      this.isLoading = !0;
    },
    stopLoading() {
      this.isLoading = !1;
    },
    validate(s = 800, e) {
      this.isInvalid = !1, this.isValid = !0;
      const i = e ? s - 300 : s;
      return new Promise(
        (a) => setTimeout(e ? () => this.clear().then(() => a(!0)) : () => a(!0), i)
      );
    },
    invalidate(s = 1100, e) {
      this.isValid = !1, this.isInvalid = !0;
      const i = e ? s - 300 : s;
      return new Promise(
        (a) => setTimeout(e ? () => this.clear().then(() => a(!0)) : () => a(!0), i)
      );
    },
    clear(s = 300) {
      return this.isValid = !1, this.isInvalid = !1, this.isLoading = !1, new Promise((e) => {
        setTimeout(() => {
          e(!0);
        }, s);
      });
    }
  });
}
const V = /* @__PURE__ */ m({
  inheritAttrs: !1,
  __name: "ScalarLoading",
  props: {
    loadingState: {},
    size: {}
  },
  setup(s) {
    const { cx: e } = f(), i = c({
      variants: {
        size: {
          xs: "size-3",
          sm: "size-3.5",
          md: "size-4",
          lg: "size-5",
          xl: "size-6",
          "2xl": "size-8",
          "3xl": "size-10",
          full: "size-full"
        }
      },
      defaultVariants: {
        size: "full"
      }
    });
    return (a, r) => a.loadingState ? (t(), l("div", h(p({ key: 0 }, n(e)("loader-wrapper", n(i)({ size: a.size })))), [
      (t(), l("svg", {
        class: o(["svg-loader", {
          "icon-is-valid": a.loadingState.isValid,
          "icon-is-invalid": a.loadingState.isInvalid
        }]),
        viewBox: "0 0 100 100",
        xmlns: "http://www.w3.org/2000/svg",
        "xmlns:xlink": "http://www.w3.org/1999/xlink"
      }, [
        r[0] || (r[0] = g('<path class="svg-path svg-check-mark" d="m 0 60 l 30 30 l 70 -80" data-v-65265e87></path><path class="svg-path svg-x-mark" d="m 50 50 l 40 -40" data-v-65265e87></path><path class="svg-path svg-x-mark" d="m 50 50 l 40 40" data-v-65265e87></path><path class="svg-path svg-x-mark" d="m 50 50 l -40 -40" data-v-65265e87></path><path class="svg-path svg-x-mark" d="m 50 50 l -40 40" data-v-65265e87></path>', 5)),
        a.loadingState.isLoading ? (t(), l("g", z, [
          v("circle", {
            class: o(["loader-path", {
              "loader-path-off": a.loadingState.isValid || a.loadingState.isInvalid
            }]),
            cx: "50",
            cy: "50",
            fill: "none",
            r: "20",
            "stroke-width": "2"
          }, null, 2)
        ])) : d("", !0)
      ], 2))
    ], 16)) : d("", !0);
  }
});
export {
  V as default,
  S as useLoadingState
};
