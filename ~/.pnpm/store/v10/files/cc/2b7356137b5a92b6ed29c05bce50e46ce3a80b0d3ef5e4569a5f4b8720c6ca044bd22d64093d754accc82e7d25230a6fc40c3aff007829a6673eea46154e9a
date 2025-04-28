import { objectMerge as m } from "@scalar/oas-utils/helpers";
import { createHead as p } from "@unhead/vue";
import { reactive as f, createApp as s } from "vue";
import d from "./components/ApiReference.vue.js";
/* empty css                             */
function j(n, c, a = !0) {
  const t = f(c), r = s(d, { configuration: t }), i = p();
  r.use(i);
  function o(e = n) {
    if (!e) {
      console.warn(
        "Invalid HTML element provided. Cannot mount Scalar References"
      );
      return;
    }
    r.mount(e);
  }
  return a && o(), {
    /** Update the configuration for a mounted reference */
    updateConfig(e, u = !0) {
      u ? Object.assign(t, e) : m(t, e);
    },
    updateSpec(e) {
      t.spec = e;
    },
    /** Mount the references to a given element */
    mount: o,
    /** Unmount the app from an element */
    unmount: () => r.unmount()
  };
}
export {
  j as createScalarReferences
};
