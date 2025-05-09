import { defineComponent as p, useId as m, openBlock as V, createBlock as f, mergeProps as c, unref as r, withCtx as s, createElementVNode as y, renderSlot as u } from "vue";
import b from "../../../../components/DataTable/DataTableInput.vue.js";
const v = ["for"], k = /* @__PURE__ */ p({
  __name: "RequestAuthDataTableInput",
  props: {
    type: {},
    containerClass: {},
    required: { type: Boolean, default: !1 },
    modelValue: {},
    readOnly: { type: Boolean, default: !1 },
    environment: {},
    envVariables: {},
    workspace: {}
  },
  emits: ["update:modelValue", "inputFocus", "inputBlur", "selectVariable"],
  setup(i, { emit: d }) {
    const e = i, a = d, l = m();
    return (o, n) => (V(), f(b, c({
      id: r(l),
      canAddCustomEnumValue: !e.readOnly,
      containerClass: e.containerClass
    }, o.$attrs, {
      envVariables: e.envVariables,
      environment: e.environment,
      modelValue: e.modelValue,
      readOnly: e.readOnly,
      required: e.required,
      type: e.type,
      workspace: e.workspace,
      onInputBlur: n[0] || (n[0] = (t) => a("inputBlur")),
      onInputFocus: n[1] || (n[1] = (t) => a("inputFocus")),
      onSelectVariable: n[2] || (n[2] = (t) => a("selectVariable", t)),
      "onUpdate:modelValue": n[3] || (n[3] = (t) => a("update:modelValue", t))
    }), {
      default: s(() => [
        y("label", { for: r(l) }, [
          u(o.$slots, "default")
        ], 8, v)
      ]),
      icon: s(() => [
        u(o.$slots, "icon")
      ]),
      _: 3
    }, 16, ["id", "canAddCustomEnumValue", "containerClass", "envVariables", "environment", "modelValue", "readOnly", "required", "type", "workspace"]));
  }
});
export {
  k as default
};
