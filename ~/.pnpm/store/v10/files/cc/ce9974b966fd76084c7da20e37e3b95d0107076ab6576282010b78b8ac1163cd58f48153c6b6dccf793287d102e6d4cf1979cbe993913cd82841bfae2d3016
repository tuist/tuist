import { defineComponent as v, ref as u, openBlock as b, createBlock as _, withCtx as l, createVNode as r, unref as c, createTextVNode as k } from "vue";
import { ScalarButton as C } from "@scalar/components";
import { LibraryIcon as V } from "@scalar/icons";
import { useToasts as x } from "@scalar/use-toasts";
import N from "../IconSelector.vue.js";
import { useActiveEntities as B } from "../../store/active-entities.js";
import S from "./CommandActionForm.vue.js";
import $ from "./CommandActionInput.vue.js";
import { useWorkspace as w } from "../../store/store.js";
const D = /* @__PURE__ */ v({
  __name: "CommandPaletteCollection",
  emits: ["close", "back"],
  setup(I, { emit: d }) {
    const i = d, { activeWorkspace: s } = B(), { collectionMutators: f } = w(), o = u(""), a = u("interface-content-folder"), { toast: m } = x(), p = () => {
      var n, e;
      if (!o.value) {
        m("Please enter a name before creating a collection.", "error");
        return;
      }
      if (!((n = s.value) != null && n.uid)) {
        m("No active workspace found.", "error");
        return;
      }
      f.add(
        {
          openapi: "3.1.0",
          info: {
            title: o.value,
            version: "0.0.1"
          },
          "x-scalar-icon": a.value
        },
        (e = s.value) == null ? void 0 : e.uid
      ), i("close");
    };
    return (n, e) => (b(), _(S, {
      disabled: !o.value.trim(),
      onSubmit: p
    }, {
      options: l(() => [
        r(N, {
          modelValue: a.value,
          "onUpdate:modelValue": e[2] || (e[2] = (t) => a.value = t),
          placement: "bottom-start"
        }, {
          default: l(() => [
            r(c(C), {
              class: "aspect-square h-auto px-0",
              variant: "outlined"
            }, {
              default: l(() => [
                r(c(V), {
                  class: "text-c-2 size-4 stroke-[1.75]",
                  src: a.value
                }, null, 8, ["src"])
              ]),
              _: 1
            })
          ]),
          _: 1
        }, 8, ["modelValue"])
      ]),
      submit: l(() => e[3] || (e[3] = [
        k(" Create Collection ")
      ])),
      default: l(() => [
        r($, {
          modelValue: o.value,
          "onUpdate:modelValue": e[0] || (e[0] = (t) => o.value = t),
          label: "Collection Name",
          placeholder: "Collection Name",
          onOnDelete: e[1] || (e[1] = (t) => i("back", t))
        }, null, 8, ["modelValue"])
      ]),
      _: 1
    }, 8, ["disabled"]));
  }
});
export {
  D as default
};
