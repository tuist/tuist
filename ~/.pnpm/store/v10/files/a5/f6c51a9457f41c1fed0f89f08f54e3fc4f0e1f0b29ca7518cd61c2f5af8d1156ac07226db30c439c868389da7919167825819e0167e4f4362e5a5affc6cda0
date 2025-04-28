import { defineComponent as c, ref as i, onMounted as u, openBlock as f, createBlock as m, unref as l, createCommentVNode as p } from "vue";
import { toast as t, Toaster as d } from "vue-sonner";
import { useToasts as _ } from "../hooks/useToasts.js";
const v = /* @__PURE__ */ c({
  __name: "ScalarToasts",
  setup(T) {
    const o = i(!1);
    u(() => o.value = !0);
    const e = {
      success: t.success,
      error: t.error,
      warn: t.warning,
      info: t
    }, { initializeToasts: a } = _();
    return a((s, r = "info", n = {}) => {
      (e[r] || e.info)(s, {
        duration: n.timeout || 3e3,
        description: n.description
      });
    }), (s, r) => o.value ? (f(), m(l(d), {
      key: 0,
      class: "scalar-toaster"
    })) : p("", !0);
  }
});
export {
  v as default
};
