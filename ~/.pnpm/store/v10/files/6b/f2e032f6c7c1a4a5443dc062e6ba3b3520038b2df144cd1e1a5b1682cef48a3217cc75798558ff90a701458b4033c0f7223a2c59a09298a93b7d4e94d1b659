import { defineComponent as _, ref as u, computed as h, watch as w, openBlock as m, createBlock as v, unref as i, withCtx as a, createVNode as s, createElementVNode as p, normalizeClass as I, toDisplayString as N, createTextVNode as T } from "vue";
import { ScalarModal as $, ScalarListbox as z, ScalarButton as C, ScalarIcon as B } from "@scalar/components";
import { useToasts as D } from "@scalar/use-toasts";
import U from "../../components/CommandPalette/CommandActionForm.vue.js";
import W from "../../components/CommandPalette/CommandActionInput.vue.js";
import j from "./EnvironmentColors.vue.js";
import { useWorkspace as M } from "../../store/store.js";
const P = { class: "flex items-start gap-2" }, K = /* @__PURE__ */ _({
  __name: "EnvironmentModal",
  props: {
    state: {},
    activeWorkspaceCollections: {},
    collectionId: {}
  },
  emits: ["cancel", "submit"],
  setup(x, { emit: g }) {
    const n = x, f = g, { events: E } = M(), r = u(""), c = u("#8E8E8E"), d = h(() => [
      ...n.activeWorkspaceCollections.filter((t) => {
        var e;
        return ((e = t.info) == null ? void 0 : e.title) !== "Drafts";
      }).map((t) => {
        var e;
        return {
          id: t.uid,
          label: ((e = t.info) == null ? void 0 : e.title) ?? "Untitled Collection"
        };
      })
    ]), l = u(
      d.value.find((t) => t.id === n.collectionId)
    ), { toast: S } = D(), V = (t) => {
      c.value = t;
    };
    w(
      () => n.state.open,
      (t) => {
        t && (r.value = "", c.value = "#8E8E8E", n.collectionId ? l.value = d.value.find(
          (e) => e.id === n.collectionId
        ) : l.value = void 0);
      }
    );
    const k = () => {
      var t, e, o, b;
      if (!((t = l.value) != null && t.id)) {
        S("Please select a collection before adding an environment.", "error");
        return;
      }
      f("submit", {
        name: r.value,
        color: c.value,
        type: ((e = l.value) == null ? void 0 : e.id) === "global" ? "global" : "collection",
        collectionId: ((o = l.value) == null ? void 0 : o.id) !== "global" ? (b = l.value) == null ? void 0 : b.id : void 0
      });
    }, y = () => {
      n.state.hide(), E.commandPalette.emit({ commandName: "Create Collection" });
    };
    return (t, e) => (m(), v(i($), {
      bodyClass: "border-t-0 rounded-t-lg",
      size: "xs",
      state: t.state
    }, {
      default: a(() => [
        s(U, {
          disabled: !l.value,
          onCancel: e[2] || (e[2] = (o) => f("cancel")),
          onSubmit: k
        }, {
          options: a(() => [
            s(i(z), {
              modelValue: l.value,
              "onUpdate:modelValue": e[1] || (e[1] = (o) => l.value = o),
              options: d.value,
              placeholder: "Select Type"
            }, {
              default: a(() => [
                d.value.length > 0 ? (m(), v(i(C), {
                  key: 0,
                  class: "hover:bg-b-2 max-h-8 w-fit justify-between gap-1 p-2 text-xs",
                  variant: "outlined"
                }, {
                  default: a(() => [
                    p("span", {
                      class: I(l.value ? "text-c-1" : "text-c-3")
                    }, N(l.value ? l.value.label : "Select Collection"), 3),
                    s(i(B), {
                      class: "text-c-3",
                      icon: "ChevronDown",
                      size: "xs"
                    })
                  ]),
                  _: 1
                })) : (m(), v(i(C), {
                  key: 1,
                  class: "hover:bg-b-2 max-h-8 justify-between gap-1 p-2 text-xs",
                  variant: "outlined",
                  onClick: y
                }, {
                  default: a(() => e[3] || (e[3] = [
                    p("span", { class: "text-c-1" }, "Create Collection", -1)
                  ])),
                  _: 1
                }))
              ]),
              _: 1
            }, 8, ["modelValue", "options"])
          ]),
          submit: a(() => e[4] || (e[4] = [
            T(" Add Environment ")
          ])),
          default: a(() => [
            p("div", P, [
              s(j, {
                activeColor: c.value,
                class: "peer",
                selector: "",
                onSelect: V
              }, null, 8, ["activeColor"]),
              s(W, {
                modelValue: r.value,
                "onUpdate:modelValue": e[0] || (e[0] = (o) => r.value = o),
                class: "-mt-[.5px] !p-0 peer-has-[.color-selector]:hidden",
                placeholder: "Environment name"
              }, null, 8, ["modelValue"])
            ])
          ]),
          _: 1
        }, 8, ["disabled"])
      ]),
      _: 1
    }, 8, ["state"]));
  }
});
export {
  K as default
};
