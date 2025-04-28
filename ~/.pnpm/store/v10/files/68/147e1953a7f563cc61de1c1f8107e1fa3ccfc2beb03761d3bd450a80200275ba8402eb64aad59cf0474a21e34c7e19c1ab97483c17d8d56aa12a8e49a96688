import { defineComponent as m, computed as v, openBlock as l, createElementBlock as o, normalizeClass as b, createElementVNode as u, renderSlot as _, Fragment as s, renderList as r, toDisplayString as p } from "vue";
const g = { class: "text-select-label" }, f = ["aria-controls", "tabindex", "value"], k = ["label"], y = ["value"], V = ["value"], S = /* @__PURE__ */ m({
  __name: "TextSelect",
  props: {
    modelValue: {},
    options: {},
    controls: {}
  },
  emits: ["update:modelValue"],
  setup(i) {
    const d = i, c = v(
      () => d.options.flatMap((e) => e.options ?? e).length
    );
    return (e, n) => (l(), o("label", {
      class: b(["text-select", c.value === 1 ? "text-select--single-option" : ""])
    }, [
      u("span", g, [
        _(e.$slots, "default")
      ]),
      u("select", {
        "aria-controls": e.controls,
        tabindex: e.options.length === 1 ? -1 : 0,
        value: e.modelValue,
        onInput: n[0] || (n[0] = (t) => e.$emit("update:modelValue", t.target.value))
      }, [
        (l(!0), o(s, null, r(e.options, (t) => (l(), o(s, {
          key: t.value
        }, [
          t.options ? (l(), o("optgroup", {
            key: 0,
            label: t.label
          }, [
            (l(!0), o(s, null, r(t.options, (a) => (l(), o("option", {
              key: a.value,
              value: a.value
            }, p(a.label), 9, y))), 128))
          ], 8, k)) : (l(), o("option", {
            key: t.value,
            value: t.value
          }, p(t.label), 9, V))
        ], 64))), 128))
      ], 40, f)
    ], 2));
  }
});
export {
  S as default
};
