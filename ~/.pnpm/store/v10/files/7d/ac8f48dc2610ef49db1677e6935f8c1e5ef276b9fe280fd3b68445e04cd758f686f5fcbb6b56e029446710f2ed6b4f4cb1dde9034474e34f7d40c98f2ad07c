import { defineComponent as n, openBlock as a, createElementBlock as m, Fragment as s, createVNode as r, withCtx as p, createTextVNode as i, createCommentVNode as d } from "vue";
import u from "./OperationResponses.vue.js";
import k from "./RequestBody.vue.js";
const c = /* @__PURE__ */ n({
  __name: "Webhook",
  props: {
    webhook: {}
  },
  setup(l) {
    return (e, o) => {
      var t;
      return e.webhook ? (a(), m(s, { key: 0 }, [
        r(k, {
          class: "webhook-request-body",
          requestBody: (t = e.webhook.information) == null ? void 0 : t.requestBody
        }, {
          title: p(() => o[0] || (o[0] = [
            i("Payload")
          ])),
          _: 1
        }, 8, ["requestBody"]),
        r(u, { operation: e.webhook }, null, 8, ["operation"])
      ], 64)) : d("", !0);
    };
  }
});
export {
  c as default
};
