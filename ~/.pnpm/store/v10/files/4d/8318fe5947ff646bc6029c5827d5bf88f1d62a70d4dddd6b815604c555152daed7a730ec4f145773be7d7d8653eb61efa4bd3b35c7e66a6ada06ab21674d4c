import { defineComponent as u, computed as c, openBlock as r, createBlock as t, unref as o, isRef as s } from "vue";
import { useColorMode as p } from "@scalar/use-hooks/useColorMode";
import f from "./ScalarColorModeToggleButton.vue.js";
import _ from "./ScalarColorModeToggleIcon.vue.js";
const k = {}, S = /* @__PURE__ */ u({
  ...k,
  __name: "ScalarColorModeToggle",
  props: {
    variant: { default: "switch" }
  },
  setup(g) {
    const { isDarkMode: e, toggleColorMode: n, darkLightMode: i } = p(), l = c(
      () => e.value ? "Set light mode" : "Set dark mode"
    );
    return (d, a) => d.variant === "switch" ? (r(), t(f, {
      key: 0,
      modelValue: o(e),
      "onUpdate:modelValue": a[0] || (a[0] = (m) => s(e) ? e.value = m : null),
      "aria-label": l.value
    }, null, 8, ["modelValue", "aria-label"])) : (r(), t(_, {
      key: 1,
      "aria-label": l.value,
      mode: o(i),
      onClick: o(n)
    }, null, 8, ["aria-label", "mode", "onClick"]));
  }
});
export {
  S as default
};
