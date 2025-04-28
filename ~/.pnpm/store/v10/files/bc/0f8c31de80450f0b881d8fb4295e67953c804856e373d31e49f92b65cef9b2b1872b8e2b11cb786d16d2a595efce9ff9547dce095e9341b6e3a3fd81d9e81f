import { defineComponent as c, ref as p, onMounted as m, watch as f, onBeforeUnmount as s, openBlock as d, createElementBlock as v } from "vue";
import { useWorkspace as x } from "@scalar/api-client/store";
import { watchDebounced as g } from "@vueuse/core";
import { useApiClient as k } from "./useApiClient.js";
import { useExampleStore as C } from "../../legacy/stores/useExampleStore.js";
const A = /* @__PURE__ */ c({
  __name: "ApiClientModal",
  props: {
    configuration: {}
  },
  setup(r) {
    const t = p(null), { client: o, init: a } = k(), { selectedExampleKey: l, operationId: u } = C(), i = x();
    return m(() => {
      t.value && a({
        el: t.value,
        configuration: r.configuration,
        store: i
      });
    }), g(
      () => r.configuration,
      (e) => {
        var n;
        return e && ((n = o.value) == null ? void 0 : n.updateConfig(e));
      },
      { deep: !0, debounce: 300 }
    ), f(l, (e) => {
      o.value && e && u.value && o.value.updateExample(e, u.value);
    }), s(() => {
      var e;
      return (e = o.value) == null ? void 0 : e.app.unmount();
    }), (e, n) => (d(), v("div", {
      ref_key: "el",
      ref: t
    }, null, 512));
  }
});
export {
  A as default
};
