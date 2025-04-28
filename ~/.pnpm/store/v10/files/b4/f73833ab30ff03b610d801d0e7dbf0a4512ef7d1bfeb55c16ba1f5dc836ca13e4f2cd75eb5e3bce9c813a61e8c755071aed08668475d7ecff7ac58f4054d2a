function a() {
  const t = /* @__PURE__ */ new Set();
  function f(n) {
    return t.add(n), () => o(n);
  }
  function r(n) {
    function e(...i) {
      o(e), n(...i);
    }
    return f(e);
  }
  function o(n) {
    t.delete(n);
  }
  function c() {
    t.clear();
  }
  function u(n) {
    t == null || t.forEach((e) => e(n));
  }
  return {
    on: f,
    once: r,
    off: o,
    emit: u,
    reset: c,
    listeners: () => Array.from(t)
  };
}
export {
  a as createEventBus
};
