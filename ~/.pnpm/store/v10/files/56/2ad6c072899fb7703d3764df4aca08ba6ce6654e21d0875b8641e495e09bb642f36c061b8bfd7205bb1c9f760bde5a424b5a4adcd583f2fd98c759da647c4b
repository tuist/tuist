import { defineComponent as c, ref as i, openBlock as d, createBlock as f, withCtx as s, createTextVNode as k, createVNode as b } from "vue";
import { useToasts as w } from "@scalar/use-toasts";
import { useRouter as _ } from "vue-router";
import v from "./CommandActionForm.vue.js";
import N from "./CommandActionInput.vue.js";
import { useWorkspace as V } from "../../store/store.js";
const $ = /* @__PURE__ */ c({
  __name: "CommandPaletteWorkspace",
  emits: ["close", "back"],
  setup(W, { emit: m }) {
    const t = m, { push: n } = _(), { toast: l } = w(), { workspaceMutators: p } = V(), o = i(""), u = () => {
      if (!o.value.trim()) {
        l("Please enter a name before creating a workspace.", "error");
        return;
      }
      const r = p.add({
        name: o.value
      });
      n({
        name: "workspace",
        params: {
          workspace: r.uid
        }
      }), t("close");
    };
    return (r, e) => (d(), f(v, {
      disabled: !o.value.trim(),
      onSubmit: u
    }, {
      submit: s(() => e[2] || (e[2] = [
        k("Create Workspace")
      ])),
      default: s(() => [
        b(N, {
          modelValue: o.value,
          "onUpdate:modelValue": e[0] || (e[0] = (a) => o.value = a),
          label: "Workspace Name",
          placeholder: "Workspace Name",
          onOnDelete: e[1] || (e[1] = (a) => t("back", a))
        }, null, 8, ["modelValue"])
      ]),
      _: 1
    }, 8, ["disabled"]));
  }
});
export {
  $ as default
};
