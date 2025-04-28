const o = {
  toast: () => null
};
function a(t) {
  o.toast = t;
}
function i() {
  return {
    initializeToasts: a,
    toast: (t, s = "info", n = { timeout: 3e3 }) => {
      o.toast(t, s, n);
    }
  };
}
export {
  a as initializeToasts,
  i as useToasts
};
