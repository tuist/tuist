import { collectionSchema as x } from "@scalar/oas-utils/entities/spec";
import { LS_KEYS as p } from "@scalar/oas-utils/helpers";
import { mutationFactory as S } from "@scalar/object-utils/mutator-record";
import { reactive as u } from "vue";
function T(s) {
  const i = u({}), a = S(i, u({}), s && p.COLLECTION);
  return {
    collections: i,
    collectionMutators: a
  };
}
function Y({
  requests: s,
  requestMutators: i,
  requestExamples: a,
  requestExampleMutators: v,
  workspaces: C,
  workspaceMutators: d,
  collections: c,
  collectionMutators: l,
  tagMutators: E,
  serverMutators: h
}) {
  return {
    addCollection: (e, o) => {
      const t = x.parse(e), n = C[o];
      return n && d.edit(o, "collections", [...n.collections, t.uid]), l.add(t), t;
    },
    deleteCollection: (e, o) => {
      var t, n;
      if (o.uid) {
        if (((n = (t = c[e.uid]) == null ? void 0 : t.info) == null ? void 0 : n.title) === "Drafts") {
          console.warn("The drafts collection cannot be deleted");
          return;
        }
        if (Object.values(c).length === 1) {
          console.warn("You must have at least one collection");
          return;
        }
        e.tags.forEach((r) => E.delete(r)), e.requests.forEach((r) => {
          const f = s[r];
          f && (i.delete(r), f.examples.forEach((m) => a[m] && v.delete(m)));
        }), e.servers.forEach((r) => {
          r && h.delete(r);
        }), d.edit(
          o.uid,
          "collections",
          o.collections.filter((r) => r !== e.uid)
        ), l.delete(e.uid);
      }
    },
    addCollectionEnvironment: (e, o, t) => {
      const n = c[t];
      if (n) {
        const r = n["x-scalar-environments"] || {};
        l.edit(t, "x-scalar-environments", {
          ...r,
          [e]: o
        });
      }
    },
    removeCollectionEnvironment: (e, o) => {
      const t = c[o];
      if (t) {
        const n = t["x-scalar-environments"] || {};
        e in n && (delete n[e], l.edit(o, "x-scalar-environments", n));
      }
    }
  };
}
export {
  T as createStoreCollections,
  Y as extendedCollectionDataFactory
};
