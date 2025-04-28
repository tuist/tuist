import { defineComponent as d, openBlock as c, createBlock as m, withCtx as p, renderSlot as f } from "vue";
import u from "../IntersectionObserver.vue.js";
import { useNavState as S } from "../../hooks/useNavState.js";
import { useSidebar as _ } from "../../hooks/useSidebar.js";
const v = /* @__PURE__ */ d({
  __name: "Section",
  props: {
    id: {},
    label: {}
  },
  setup(i) {
    const e = i, { getSectionId: r, isIntersectionEnabled: n, replaceUrlState: s } = S(), { setCollapsedSidebarItem: a } = _();
    function l() {
      var t, o;
      !e.label || !n.value || (s(e.id ?? ""), ((t = e.id) != null && t.startsWith("model") || (o = e.id) != null && o.startsWith("webhook")) && a(r(e.id), !0));
    }
    return (t, o) => (c(), m(u, {
      is: "section",
      id: t.id,
      class: "section",
      onIntersecting: l
    }, {
      default: p(() => [
        f(t.$slots, "default", {}, void 0, !0)
      ]),
      _: 3
    }, 8, ["id"]));
  }
});
export {
  v as default
};
