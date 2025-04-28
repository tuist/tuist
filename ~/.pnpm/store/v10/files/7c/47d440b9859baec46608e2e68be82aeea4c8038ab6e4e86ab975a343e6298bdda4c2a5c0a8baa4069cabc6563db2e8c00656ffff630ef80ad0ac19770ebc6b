import { defineComponent as b, openBlock as y, createBlock as S, unref as s, withCtx as n, createElementVNode as r, toDisplayString as i, createVNode as m, createTextVNode as u } from "vue";
import { ScalarModal as _, ScalarButton as d } from "@scalar/components";
import { useWorkspace as g } from "../../../../store/store.js";
const k = { class: "text-c-2 mb-4 text-sm leading-normal" }, C = { class: "flex justify-between gap-2" }, B = /* @__PURE__ */ b({
  __name: "DeleteRequestAuthModal",
  props: {
    state: {},
    scheme: {}
  },
  emits: ["close", "delete"],
  setup(p, { emit: f }) {
    const l = p, c = f, { securitySchemeMutators: h } = g(), x = () => {
      var e;
      (e = l.scheme) != null && e.id && h.delete(l.scheme.id), c("delete");
    };
    return (e, t) => (y(), S(s(_), {
      size: "xxs",
      state: e.state,
      title: "Delete Security Scheme"
    }, {
      default: n(() => {
        var a;
        return [
          r("p", k, " This cannot be undone. You’re about to delete the " + i((a = e.scheme) == null ? void 0 : a.label) + " security scheme from the collection. ", 1),
          r("div", C, [
            m(s(d), {
              class: "flex h-8 cursor-pointer items-center gap-1.5 px-3 shadow-none focus:outline-none",
              type: "button",
              variant: "outlined",
              onClick: t[0] || (t[0] = (o) => c("close"))
            }, {
              default: n(() => t[1] || (t[1] = [
                u(" Cancel ")
              ])),
              _: 1
            }),
            m(s(d), {
              class: "flex h-8 cursor-pointer items-center gap-1.5 px-3 shadow-none focus:outline-none",
              type: "submit",
              onClick: x
            }, {
              default: n(() => {
                var o;
                return [
                  u(" Delete " + i((o = e.scheme) == null ? void 0 : o.label), 1)
                ];
              }),
              _: 1
            })
          ])
        ];
      }),
      _: 1
    }, 8, ["state"]));
  }
});
export {
  B as default
};
