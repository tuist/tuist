export function bindInspectorResize(divider, { availableWidth, setWidth, signal }) {
  let preferred;
  let current;
  let drag;
  const limits = () => ({ min: 180, max: Math.max(180, availableWidth() - 260 - 24) });
  const update = () => {
    const { min, max } = limits();
    current = Math.max(min, Math.min(max, preferred ?? Math.min(240, availableWidth() * 0.25)));
    setWidth(current);
    divider.setAttribute("aria-valuemin", min);
    divider.setAttribute("aria-valuemax", max);
    divider.setAttribute("aria-valuenow", Math.round(current));
  };
  const on = (name, fn) => divider.addEventListener(name, fn, { signal });
  const finish = (restore = false) => {
    if (!drag) return;
    const previous = drag;
    drag = null;
    if (restore) {
      preferred = previous.preferred;
      update();
    }
    divider.removeAttribute("data-dragging");
    if (divider.hasPointerCapture(previous.id)) divider.releasePointerCapture(previous.id);
  };
  on("pointerdown", (event) => {
    if (event.button !== 0 || drag) return;
    event.preventDefault();
    divider.focus({ preventScroll: true });
    drag = { id: event.pointerId, x: event.clientX, width: current, preferred };
    divider.setPointerCapture(event.pointerId);
    divider.setAttribute("data-dragging", "");
  });
  on("pointermove", (event) => {
    if (!drag || event.pointerId !== drag.id) return;
    const { min, max } = limits();
    preferred = Math.max(min, Math.min(max, drag.width + drag.x - event.clientX));
    update();
  });
  on("pointerup", (event) => {
    if (event.pointerId === drag?.id) finish();
  });
  on("pointercancel", () => finish(true));
  on("lostpointercapture", () => finish());
  on("keydown", (event) => {
    if (event.key === "Escape" && drag) {
      event.preventDefault();
      finish(true);
      return;
    }
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    finish();
    const { min, max } = limits();
    preferred =
      event.key === "Home" ? min : event.key === "End" ? max : current + (event.key === "ArrowLeft" ? 20 : -20);
    preferred = Math.max(min, Math.min(max, preferred));
    update();
  });
  signal.addEventListener("abort", () => finish(), { once: true });
  update();
  return update;
}
