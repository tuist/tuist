import { getHeadings as g } from "@scalar/code-highlight/markdown";
import n from "github-slugger";
const o = (t, e) => t.map((r) => ({
  ...r,
  slug: e.slug(r.value)
}));
function i(t) {
  const e = new n(), r = g(t);
  return o(r, e);
}
export {
  i as getHeadingsFromMarkdown
};
