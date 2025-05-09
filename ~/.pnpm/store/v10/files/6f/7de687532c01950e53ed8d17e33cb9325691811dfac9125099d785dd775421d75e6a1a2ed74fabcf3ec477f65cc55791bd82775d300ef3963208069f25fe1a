import { requestExampleSchema as m, collectionSchema as l } from "@scalar/oas-utils/entities/spec";
import { workspaceSchema as u } from "@scalar/oas-utils/entities/workspace";
import { LS_KEYS as f } from "@scalar/oas-utils/helpers";
import { mutationFactory as k } from "@scalar/object-utils/mutator-record";
import { reactive as d } from "vue";
import { createInitialRequest as h } from "./requests.js";
function D(o) {
  const e = d({}), r = k(e, d({}), o && f.WORKSPACE);
  return {
    workspaces: e,
    workspaceMutators: r
  };
}
function F({
  workspaces: o,
  workspaceMutators: e,
  collectionMutators: r,
  requestMutators: i,
  requestExampleMutators: p
}) {
  return {
    addWorkspace: (a = {}) => {
      const { request: t } = h(), c = m.parse({
        name: "Example",
        requestUid: t.uid
      });
      t.examples.push(c.uid);
      const s = l.parse({
        info: {
          title: "Drafts"
        },
        children: [t.uid],
        requests: [t.uid]
      }), n = u.parse({
        ...a,
        collections: [s.uid]
      });
      return p.add(c), i.add(t), r.add(s), e.add(n), n;
    },
    deleteWorkspace: (a) => {
      if (Object.keys(o).length <= 1) {
        console.warn("The last workspace cannot be deleted.");
        return;
      }
      e.delete(a);
    }
  };
}
export {
  D as createStoreWorkspaces,
  F as extendedWorkspaceDataFactory
};
