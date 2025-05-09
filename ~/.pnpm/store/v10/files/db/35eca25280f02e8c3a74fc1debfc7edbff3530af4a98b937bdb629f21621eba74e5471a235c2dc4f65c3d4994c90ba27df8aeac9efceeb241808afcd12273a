import { defineComponent as r, openBlock as i, createElementBlock as a, createVNode as o, unref as e, withCtx as t, createElementVNode as l, renderSlot as n } from "vue";
import { Disclosure as d, DisclosureButton as u, DisclosurePanel as _ } from "@headlessui/vue";
import { ScalarIcon as f } from "@scalar/components";
const p = { class: "section-accordion-wrapper" }, m = { class: "section-accordion-title" }, B = /* @__PURE__ */ r({
  __name: "SectionContainerAccordion",
  setup(h) {
    return (c, v) => (i(), a("div", p, [
      o(e(d), {
        as: "div",
        class: "section-accordion",
        defaultOpen: ""
      }, {
        default: t(({ open: s }) => [
          o(e(u), { class: "section-accordion-button" }, {
            default: t(() => [
              o(e(f), {
                class: "section-accordion-chevron",
                icon: s ? "ChevronDown" : "ChevronRight"
              }, null, 8, ["icon"]),
              l("div", m, [
                n(c.$slots, "title", {}, void 0, !0)
              ])
            ]),
            _: 2
          }, 1024),
          o(e(_), { class: "section-accordion-content" }, {
            default: t(() => [
              n(c.$slots, "default", {}, void 0, !0)
            ]),
            _: 3
          })
        ]),
        _: 3
      })
    ]));
  }
});
export {
  B as default
};
