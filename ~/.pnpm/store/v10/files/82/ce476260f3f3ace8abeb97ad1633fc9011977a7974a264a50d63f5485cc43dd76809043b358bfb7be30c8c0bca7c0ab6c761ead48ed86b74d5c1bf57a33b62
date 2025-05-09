import { environmentSchema as o } from "@scalar/oas-utils/entities/environment";
import { LS_KEYS as a } from "@scalar/oas-utils/helpers";
import { mutationFactory as m } from "@scalar/object-utils/mutator-record";
import { reactive as r } from "vue";
function f(n) {
  const t = r({}), e = m(t, r({}), n && a.ENVIRONMENT);
  return e.add(
    o.parse({
      uid: "default",
      name: "Default Environment",
      color: "#0082D0",
      value: JSON.stringify({ exampleKey: "exampleValue" }, null, 2),
      isDefault: !0
    })
  ), {
    environments: t,
    environmentMutators: e
  };
}
function d({ environmentMutators: n }) {
  return { deleteEnvironment: (e) => {
    if (e === "default") {
      console.warn("Default environment cannot be deleted.");
      return;
    }
    n.delete(e);
  } };
}
export {
  f as createStoreEnvironments,
  d as extendedEnvironmentDataFactory
};
