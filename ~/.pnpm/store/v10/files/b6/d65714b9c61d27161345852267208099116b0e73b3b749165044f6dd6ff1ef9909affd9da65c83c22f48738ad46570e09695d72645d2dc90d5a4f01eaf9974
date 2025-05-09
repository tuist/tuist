import { defineComponent as n, openBlock as s, createElementBlock as m, unref as e, createTextVNode as p, createVNode as i } from "vue";
import { ScalarIcon as a } from "@scalar/components";
import { useSidebar as l } from "../hooks/useSidebar.js";
const S = /* @__PURE__ */ n({
  __name: "ShowMoreButton",
  props: {
    id: {}
  },
  setup(u) {
    const { setCollapsedSidebarItem: t } = l();
    return (r, o) => (s(), m("button", {
      class: "show-more",
      type: "button",
      onClick: o[0] || (o[0] = (c) => e(t)(r.id, !0))
    }, [
      o[1] || (o[1] = p(" Show More ")),
      i(e(a), {
        class: "show-more-icon",
        icon: "ChevronDown"
      })
    ]));
  }
});
export {
  S as default
};
