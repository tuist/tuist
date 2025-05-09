import { objectMerge as p } from "@scalar/oas-utils/helpers";
import { snippetz as k } from "@scalar/snippetz";
import { computed as o, ref as d, reactive as m, readonly as a } from "vue";
const y = {
  targetKey: "shell",
  clientKey: "curl"
}, { clients: A } = k();
function C(t) {
  var n;
  return ((n = r.value.find((e) => e.key === t.targetKey)) == null ? void 0 : n.title) ?? t.targetKey;
}
function K(t) {
  var n, e;
  return ((e = (n = r.value.find((i) => i.key === t.targetKey)) == null ? void 0 : n.clients.find((i) => i.client === t.clientKey)) == null ? void 0 : e.title) ?? t.clientKey;
}
const H = o(() => C(l)), b = o(() => K(l));
function h(t, n) {
  return n.value === !0 ? [] : t.flatMap((e) => {
    var i;
    return typeof n.value != "object" ? [] : Array.isArray(n.value) ? (e.clients = e.clients.filter(
      // @ts-expect-error Typescript, chill. It’s all good. It has to be an array.
      (s) => !n.value.includes(s.client)
    ), e.clients.length ? [e] : []) : n.value[e.key] === !0 ? [] : (Array.isArray(n.value[e.key]) && (e.clients = e.clients.filter((s) => !// @ts-expect-error We checked whether it’s an Array already.
    n.value[e.key].includes(s.client))), (i = e == null ? void 0 : e.clients) != null && i.length ? [e] : []);
  });
}
const r = o(() => h(A(), c)), c = d({}), f = d();
function j(t) {
  t !== void 0 && (f.value = t, T(u()));
}
const u = () => {
  var t, n, e, i;
  return v(f.value) ? f.value : v(y) ? y : {
    targetKey: (t = r.value[0]) == null ? void 0 : t.key,
    clientKey: (i = (e = (n = r.value[0]) == null ? void 0 : n.clients) == null ? void 0 : e[0]) == null ? void 0 : i.client
  };
};
function v(t) {
  return t === void 0 ? !1 : !!r.value.find(
    (n) => n.key === t.targetKey && n.clients.find((e) => e.client === t.clientKey)
  );
}
function L() {
  p(l, u());
}
const l = m(u()), T = (t) => {
  Object.assign(l, {
    ...l,
    ...t
  });
}, S = () => ({
  httpClient: a(l),
  resetState: L,
  setHttpClient: T,
  setDefaultHttpClient: j,
  excludedClients: a(c),
  setExcludedClients: (t) => {
    c.value = t, p(l, u());
  },
  availableTargets: r,
  getClientTitle: K,
  getTargetTitle: C,
  httpTargetTitle: H,
  httpClientTitle: b
});
export {
  h as filterHiddenClients,
  S as useHttpClientStore
};
