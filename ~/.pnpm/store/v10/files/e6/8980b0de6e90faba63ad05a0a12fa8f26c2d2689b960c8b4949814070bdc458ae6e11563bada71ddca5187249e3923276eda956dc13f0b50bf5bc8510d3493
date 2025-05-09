import { securitySchemeSchema as n } from "@scalar/oas-utils/entities/spec";
import { LS_KEYS as h } from "@scalar/oas-utils/helpers";
import { mutationFactory as o } from "@scalar/object-utils/mutator-record";
import { reactive as f } from "vue";
function v(S) {
  const i = f({}), u = o(
    i,
    f({}),
    S && h.SECURITY_SCHEME
  );
  return {
    securitySchemes: i,
    securitySchemeMutators: u
  };
}
function k({
  securitySchemeMutators: S,
  collectionMutators: i,
  collections: u,
  requests: s,
  requestMutators: y
}) {
  return {
    addSecurityScheme: (t, e) => {
      const r = n.parse(t);
      return S.add(r), e && u[e] && i.edit(e, "securitySchemes", [
        ...u[e].securitySchemes,
        r.uid
      ]), r;
    },
    deleteSecurityScheme: (t) => {
      Object.values(u).forEach((e) => {
        e.securitySchemes.includes(t) && i.edit(
          e.uid,
          "securitySchemes",
          e.securitySchemes.filter((r) => r !== t)
        );
      }), Object.values(s).forEach((e) => {
        var r, m, d, a;
        (r = e.security) != null && r.some((c) => Object.keys(c).includes(t)) && y.edit(
          e.uid,
          "security",
          (d = (m = s[e.uid]) == null ? void 0 : m.security) == null ? void 0 : d.filter((c) => !Object.keys(c).includes(t))
        ), e.selectedSecuritySchemeUids.flat().includes(t) && y.edit(
          e.uid,
          "selectedSecuritySchemeUids",
          (a = e.selectedSecuritySchemeUids) == null ? void 0 : a.filter((c) => Array.isArray(c) ? !c.includes(t) : c !== t)
        );
      }), S.delete(t);
    }
  };
}
export {
  v as createStoreSecuritySchemes,
  k as extendedSecurityDataFactory
};
