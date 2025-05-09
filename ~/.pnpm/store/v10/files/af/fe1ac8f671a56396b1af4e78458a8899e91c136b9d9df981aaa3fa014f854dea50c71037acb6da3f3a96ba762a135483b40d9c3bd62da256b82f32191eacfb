import { defineComponent as d, openBlock as l, createBlock as i, withCtx as a, renderSlot as t, createVNode as r, unref as o } from "vue";
import { TabGroup as m, TabList as u } from "@headlessui/vue";
import f from "./CardHeader.vue.js";
const g = /* @__PURE__ */ d({
  __name: "CardTabHeader",
  emits: ["change"],
  setup(p, { emit: s }) {
    const c = s, n = (e) => {
      c("change", e);
    };
    return (e, _) => (l(), i(f, { class: "scalar-card-header scalar-card-header-tabs" }, {
      actions: a(() => [
        t(e.$slots, "actions", {}, void 0, !0)
      ]),
      default: a(() => [
        r(o(m), { onChange: n }, {
          default: a(() => [
            r(o(u), { class: "tab-list custom-scroll" }, {
              default: a(() => [
                t(e.$slots, "default", {}, void 0, !0)
              ]),
              _: 3
            })
          ]),
          _: 3
        })
      ]),
      _: 3
    }));
  }
});
export {
  g as default
};
