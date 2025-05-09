import { serverSchema as o } from "@scalar/oas-utils/entities/spec";
import { LS_KEYS as u } from "@scalar/oas-utils/helpers";
import { mutationFactory as a } from "@scalar/object-utils/mutator-record";
import { reactive as m } from "vue";
function R(s) {
  const r = m({}), v = a(r, m({}), s && u.SERVER);
  return {
    servers: r,
    serverMutators: v
  };
}
function h({
  serverMutators: s,
  collections: r,
  collectionMutators: v,
  requests: f,
  requestMutators: d
}) {
  return {
    addServer: (S, e) => {
      const t = o.parse(S);
      return r[e] ? v.edit(e, "servers", [
        ...r[e].servers,
        t.uid
      ]) : f[e] && d.edit(e, "servers", [...f[e].servers, t.uid]), s.add(t), t;
    },
    deleteServer: (S, e) => {
      r[e] && (v.edit(
        e,
        "servers",
        r[e].servers.filter((t) => t !== S)
      ), s.delete(S));
    }
  };
}
export {
  R as createStoreServers,
  h as extendedServerDataFactory
};
