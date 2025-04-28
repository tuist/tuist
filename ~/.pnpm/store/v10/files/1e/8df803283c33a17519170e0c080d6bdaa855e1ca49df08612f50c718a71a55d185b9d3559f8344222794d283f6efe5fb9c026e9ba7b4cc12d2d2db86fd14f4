import { defineComponent as a, onMounted as o } from "vue";
const c = /* @__PURE__ */ a({
  __name: "UrlQueryParameterChecker",
  emits: ["input"],
  setup(u, { emit: t }) {
    const n = t;
    return o(() => {
      const e = new URLSearchParams(window.location.search), r = e.get("url");
      r && n(
        "input",
        r,
        e.get("integration"),
        "query"
      );
    }), (e, r) => null;
  }
});
export {
  c as default
};
