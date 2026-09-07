export function bindDragFocus(element, { geometry, preview, focus, signal }) {
  let drag = null;
  let suppressClick = false;
  const on = (target, name, handler, options = {}) => target.addEventListener(name, handler, { ...options, signal });
  const position = (event) => Math.max(0, Math.min(1, (event.clientX - drag.left) / drag.width));
  const cancel = () => {
    if (!drag) return;
    const { pointerId, moved, capture } = drag;
    drag = null;
    suppressClick ||= moved;
    preview(null);
    if (capture.hasPointerCapture(pointerId)) capture.releasePointerCapture(pointerId);
  };
  const update = (event) => {
    const current = position(event);
    drag.moved ||= Math.abs(current - drag.anchor) * drag.width >= 4;
    const left = Math.min(current, drag.anchor);
    const width = Math.abs(current - drag.anchor);
    const range = { start: drag.start + left * drag.span, span: width * drag.span };
    if (drag.moved) preview({ ...range, left, width });
    return range;
  };
  on(element, "pointerdown", (event) => {
    if (event.button !== 0 || event.isPrimary === false) return;
    cancel();
    suppressClick = false;
    drag = { ...geometry(), pointerId: event.pointerId, moved: false, capture: event.target };
    if (drag.width <= 0) {
      drag = null;
      return;
    }
    drag.anchor = position(event);
    (event.target.tabIndex >= 0 ? event.target : element).focus({ preventScroll: true });
    drag.capture.setPointerCapture(event.pointerId);
  });
  on(element, "pointermove", (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    update(event);
    if (drag.moved) event.preventDefault();
  });
  on(element, "pointerup", (event) => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    const range = update(event);
    const commit = drag.moved && range.span > 0;
    cancel();
    if (commit) focus(range);
  });
  on(element, "pointercancel", cancel);
  on(element, "lostpointercapture", cancel);
  on(element, "keydown", (event) => {
    if (event.key === "Escape" && drag) {
      event.preventDefault();
      cancel();
    }
  });
  on(
    element,
    "click",
    (event) => {
      if (!suppressClick) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      suppressClick = false;
    },
    { capture: true },
  );
  if (element.ownerDocument?.defaultView) on(element.ownerDocument.defaultView, "blur", cancel);
  return cancel;
}
