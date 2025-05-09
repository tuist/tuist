import { defineComponent as d, ref as f, watch as r, openBlock as x, createBlock as V, withCtx as s, createVNode as b, createTextVNode as p, toDisplayString as v } from "vue";
import _ from "../../components/ScreenReader.vue.js";
import y from "./TextSelect.vue.js";
/* empty css                */
const O = /* @__PURE__ */ d({
  __name: "ExamplePicker",
  props: {
    examples: {}
  },
  emits: ["update:modelValue"],
  setup(n, { emit: u }) {
    const a = n, i = u, l = f(Object.keys(a.examples)[0]);
    function c(e) {
      e && (l.value = e);
    }
    r(
      () => a.examples,
      () => {
        c(Object.keys(a.examples)[0]);
      },
      { immediate: !0 }
    ), r(
      l,
      () => {
        l.value && i("update:modelValue", l.value);
      },
      { immediate: !0 }
    );
    function o(e) {
      if (!e)
        return "Select an example";
      const t = a.examples[e];
      return (t == null ? void 0 : t.summary) ?? e;
    }
    return (e, t) => (x(), V(y, {
      modelValue: l.value,
      "onUpdate:modelValue": t[0] || (t[0] = (m) => l.value = m),
      class: "example-selector",
      options: Object.keys(e.examples).map((m) => ({
        label: o(m),
        value: m
      }))
    }, {
      default: s(() => [
        b(_, null, {
          default: s(() => t[1] || (t[1] = [
            p("Selected Example Values:")
          ])),
          _: 1
        }),
        p(" " + v(o(l.value)), 1)
      ]),
      _: 1
    }, 8, ["modelValue", "options"]));
  }
});
export {
  O as default
};
