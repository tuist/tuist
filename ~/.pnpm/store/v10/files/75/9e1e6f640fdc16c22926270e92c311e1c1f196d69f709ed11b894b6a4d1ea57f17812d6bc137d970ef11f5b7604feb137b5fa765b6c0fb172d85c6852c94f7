import { defineComponent as m, computed as r, openBlock as a, createElementBlock as c, normalizeProps as p, guardReactiveProps as s, unref as u, toDisplayString as f } from "vue";
import { useBindCx as l } from "@scalar/components";
import { isMacOS as x } from "@scalar/use-tooltip";
const b = /* @__PURE__ */ m({
  __name: "ScalarHotkey",
  props: {
    hotkey: {},
    modifier: {}
  },
  setup(t) {
    const e = t, { cx: i } = l(), o = r(() => e.modifier || "meta"), n = r(() => `${o.value === "meta" ? x() ? "⌘" : "^" : o.value} ${e.hotkey}`);
    return (d, y) => (a(), c("div", p(s(
      u(i)(
        "border-b-3 inline-block overflow-hidden rounded border-1/2 text-xxs rounded-b px-1 font-medium uppercase"
      )
    )), f(n.value), 17));
  }
});
export {
  b as default
};
