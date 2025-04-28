import { defineComponent as t, computed as n, onServerPrefetch as l, openBlock as m, createElementBlock as s, normalizeClass as p, normalizeStyle as i } from "vue";
import { htmlFromMarkdown as c } from "@scalar/code-highlight";
import { sleep as f } from "../../helpers/oas-utils.js";
const u = ["innerHTML"], w = /* @__PURE__ */ t({
  __name: "ScalarMarkdown",
  props: {
    value: {},
    withImages: { type: Boolean, default: !1 },
    transform: {},
    transformType: {},
    clamp: { type: [String, Boolean] }
  },
  setup(a) {
    const e = a, o = n(
      () => c(e.value ?? "", {
        removeTags: e.withImages ? [] : ["img", "picture"],
        transform: e.transform,
        transformType: e.transformType
      })
    );
    return l(async () => await f(1)), (r, d) => (m(), s("div", {
      class: p(["markdown text-ellipsis", { "line-clamp-4": r.clamp }]),
      style: i({
        "-webkit-line-clamp": typeof r.clamp == "string" ? r.clamp : void 0
      }),
      innerHTML: o.value
    }, null, 14, u));
  }
});
export {
  w as default
};
