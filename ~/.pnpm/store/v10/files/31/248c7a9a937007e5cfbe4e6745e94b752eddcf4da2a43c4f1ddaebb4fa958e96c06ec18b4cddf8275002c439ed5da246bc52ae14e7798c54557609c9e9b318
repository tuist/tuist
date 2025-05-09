import { replaceTemplateVariables as n } from "../string-template.js";
import { cookieSchema as d } from "@scalar/oas-utils/entities/cookie";
import { isDefined as w } from "@scalar/oas-utils/helpers";
const $ = (l = [], i = {}, s = "") => {
  const t = {}, e = [], f = new URLSearchParams();
  return l.forEach((a) => {
    var p;
    if (a.type === "apiKey") {
      const o = n(a.value, i) || s;
      a.in === "header" && (t[a.name] = o), a.in === "query" && f.append(a.name, o), a.in === "cookie" && e.push(
        d.parse({
          uid: a.uid,
          name: a.name,
          value: o,
          path: "/"
        })
      );
    }
    if (a.type === "http")
      if (a.scheme === "basic") {
        const o = n(a.username, i), u = n(a.password, i), r = `${o}:${u}`;
        t.Authorization = `Basic ${r === ":" ? "username:password" : btoa(r)}`;
      } else {
        const o = n(a.token, i);
        t.Authorization = `Bearer ${o || s}`;
      }
    if (a.type === "oauth2") {
      const u = (p = Object.values(a.flows).filter(w).find((r) => r.token)) == null ? void 0 : p.token;
      t.Authorization = `Bearer ${u || s}`;
    }
  }), { headers: t, cookies: e, urlParams: f };
};
export {
  $ as buildRequestSecurity
};
