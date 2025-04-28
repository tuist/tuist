import { PathId as e } from "../routes.js";
function n(t) {
  return () => {
    const a = {
      [e.Collection]: "default",
      [e.Environment]: "default",
      [e.Request]: "default",
      [e.Examples]: "default",
      [e.Schema]: "default",
      [e.Cookies]: "default",
      [e.Servers]: "default",
      [e.Workspace]: "default",
      [e.Settings]: "default"
    }, u = t == null ? void 0 : t.currentRoute.value;
    return u && Object.keys(a).forEach((f) => {
      u.params[f] && (a[f] = u.params[f]);
    }), a;
  };
}
export {
  n as getRouterParams
};
