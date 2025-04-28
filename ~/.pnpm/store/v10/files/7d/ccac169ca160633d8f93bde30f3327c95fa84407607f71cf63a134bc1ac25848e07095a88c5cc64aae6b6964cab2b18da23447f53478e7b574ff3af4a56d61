import { defineComponent as i, onMounted as r, onBeforeUnmount as c } from "vue";
const u = /* @__PURE__ */ i({
  __name: "PasteEventListener",
  emits: ["input"],
  setup(m, { emit: o }) {
    const s = o;
    r(() => {
      document.addEventListener("paste", n);
    }), c(() => {
      document.removeEventListener("paste", n);
    });
    async function n(e) {
      const t = e.target;
      if (!(t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) && e.clipboardData) {
        const a = e.clipboardData.getData("text");
        a && s("input", a, null, "paste");
      }
    }
    return (e, t) => null;
  }
});
export {
  u as default
};
