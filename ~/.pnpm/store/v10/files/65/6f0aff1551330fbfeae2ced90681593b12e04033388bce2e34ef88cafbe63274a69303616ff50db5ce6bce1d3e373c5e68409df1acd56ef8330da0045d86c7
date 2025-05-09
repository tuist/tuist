import { defineComponent as i, computed as s, openBlock as m, createElementBlock as l, createVNode as u, unref as d, createTextVNode as f, createCommentVNode as g } from "vue";
import { ScalarIcon as h } from "@scalar/components";
import { makeUrlAbsolute as p } from "@scalar/oas-utils/helpers";
const k = ["href"], v = /* @__PURE__ */ i({
  __name: "OpenApiClientButton",
  props: {
    buttonSource: {},
    source: { default: "api-reference" },
    isDevelopment: { type: Boolean },
    integration: {},
    url: {}
  },
  setup(o) {
    const a = s(() => {
      const c = o.url ?? (typeof window < "u" ? window.location.href : void 0), t = p(c);
      if (!(t != null && t.length))
        return;
      const e = new URL(
        o.isDevelopment ? "http://localhost:5065" : "https://client.scalar.com"
      );
      if (e.searchParams.set("url", t), o.integration !== null && e.searchParams.set("integration", o.integration ?? "vue"), e.searchParams.set("utm_source", "api-reference"), e.searchParams.set("utm_medium", "button"), e.searchParams.set("utm_campaign", o.buttonSource), o.source === "gitbook") {
        e.searchParams.set("utm_source", "gitbook");
        const n = document.querySelector("img.dark\\:block[alt='Logo']"), r = document.querySelector("img.dark\\:hidden[alt='Logo']");
        n && n instanceof HTMLImageElement && e.searchParams.set("dark_logo", encodeURIComponent(n.src)), r && r instanceof HTMLImageElement && e.searchParams.set("light_logo", encodeURIComponent(r.src));
      }
      return e.toString();
    });
    return (c, t) => a.value ? (m(), l("a", {
      key: 0,
      class: "open-api-client-button",
      href: a.value,
      target: "_blank"
    }, [
      u(d(h), {
        icon: "ExternalLink",
        size: "xs",
        thickness: "2.5"
      }),
      t[0] || (t[0] = f(" Open API Client "))
    ], 8, k)) : g("", !0);
  }
});
export {
  v as default
};
