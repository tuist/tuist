import { createExampleFromRequest as c } from "@scalar/oas-utils/entities/spec";
import { LS_KEYS as x, iterateTitle as u } from "@scalar/oas-utils/helpers";
import { mutationFactory as E } from "@scalar/object-utils/mutator-record";
import { reactive as n } from "vue";
function L(o) {
  const t = n({}), m = E(
    t,
    n({}),
    o && x.REQUEST_EXAMPLE
  );
  return {
    requestExamples: t,
    requestExampleMutators: m
  };
}
function T({
  requestExamples: o,
  requestExampleMutators: t,
  requestMutators: m,
  requests: l
}) {
  return {
    addRequestExample: (e, a) => {
      const i = a ?? u(
        (e.summary ?? "Example") + " #1",
        (p) => e.examples.some((s) => {
          var d;
          return ((d = o[s]) == null ? void 0 : d.name) === p;
        })
      ), r = c(e, i);
      return t.add(r), m.edit(e.uid, "examples", [...e.examples, r.uid]), r;
    },
    deleteRequestExample: (e) => {
      var a;
      e.requestUid && (m.edit(
        e.requestUid,
        "examples",
        ((a = l[e.requestUid]) == null ? void 0 : a.examples.filter((i) => i !== e.uid)) || []
      ), t.delete(e.uid));
    }
  };
}
export {
  L as createStoreRequestExamples,
  T as extendedExampleDataFactory
};
