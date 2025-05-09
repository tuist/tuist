import { ref as m, readonly as d } from "vue";
function n({
  multiple: u,
  accept: c,
  onChange: l,
  onError: t
} = {}) {
  const i = m(null);
  let e;
  typeof document < "u" && (e = document.createElement("input"), e.type = "file", e.onchange = (p) => {
    const s = p.target;
    i.value = s.files, l == null || l(i.value);
  }, e.onerror = () => t == null ? void 0 : t(), e.multiple = u, e.accept = c);
  const f = () => {
    if (!e) return t == null ? void 0 : t();
    e.click();
  };
  return {
    files: d(i),
    open: f
  };
}
export {
  n as useFileDialog
};
