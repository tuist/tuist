import { defineComponent as p, ref as m, openBlock as c, createBlock as f, withCtx as t, createVNode as s, unref as e, normalizeClass as _, createElementVNode as a, renderSlot as n, createElementBlock as d, createCommentVNode as l } from "vue";
import { Disclosure as v, DisclosureButton as h, DisclosurePanel as $ } from "@headlessui/vue";
import { ScalarIcon as k } from "@scalar/components";
import { useElementHover as C } from "@vueuse/core";
import b from "../IntersectionObserver.vue.js";
const B = { class: "section-accordion-button-content" }, y = {
  key: 0,
  class: "section-accordion-button-actions"
}, D = {
  key: 0,
  class: "section-accordion-description"
}, w = { class: "section-accordion-content-card" }, A = /* @__PURE__ */ p({
  __name: "SectionAccordion",
  props: {
    id: {},
    transparent: { type: Boolean }
  },
  setup(E) {
    const i = m(), u = C(i);
    return (o, N) => (c(), f(b, {
      id: o.id,
      class: "section-wrapper"
    }, {
      default: t(() => [
        s(e(v), {
          as: "section",
          class: _(["section-accordion", { "section-accordion-transparent": o.transparent }])
        }, {
          default: t(({ open: r }) => [
            s(e(h), {
              ref_key: "button",
              ref: i,
              class: "section-accordion-button"
            }, {
              default: t(() => [
                a("div", B, [
                  n(o.$slots, "title", {}, void 0, !0)
                ]),
                o.$slots.actions ? (c(), d("div", y, [
                  n(o.$slots, "actions", {
                    active: e(u) || r
                  }, void 0, !0)
                ])) : l("", !0),
                s(e(k), {
                  class: "section-accordion-chevron",
                  icon: r ? "ChevronDown" : "ChevronRight"
                }, null, 8, ["icon"])
              ]),
              _: 2
            }, 1536),
            s(e($), { class: "section-accordion-content" }, {
              default: t(() => [
                o.$slots.description ? (c(), d("div", D, [
                  n(o.$slots, "description", {}, void 0, !0)
                ])) : l("", !0),
                a("div", w, [
                  n(o.$slots, "default", {}, void 0, !0)
                ])
              ]),
              _: 3
            })
          ]),
          _: 3
        }, 8, ["class"])
      ]),
      _: 3
    }, 8, ["id"]));
  }
});
export {
  A as default
};
