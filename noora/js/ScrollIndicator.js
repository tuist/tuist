// Shared by table scrollbars and bounded chart viewports. The viewport remains
// the source of truth so wheel, touch, keyboard, and thumb dragging stay in sync.
export function bindScrollIndicator(
  viewport,
  track,
  thumb,
  axis = "horizontal",
  { autoUpdate = true } = {},
) {
  const horizontal = axis === "horizontal";
  const position = horizontal ? "scrollLeft" : "scrollTop";
  const extent = horizontal ? "scrollWidth" : "scrollHeight";
  const client = horizontal ? "clientWidth" : "clientHeight";
  const coordinate = horizontal ? "clientX" : "clientY";
  const size = horizontal ? "width" : "height";
  const abort = new AbortController();
  let drag;
  const on = (el, name, fn) =>
    el.addEventListener(name, fn, { signal: abort.signal });
  const metrics = () => {
    const length = track[client];
    const thumbSize = Math.min(
      length,
      Math.max(24, (length * viewport[client]) / Math.max(1, viewport[extent])),
    );
    return {
      thumbSize,
      travel: length - thumbSize,
      overflow: Math.max(0, viewport[extent] - viewport[client]),
    };
  };
  const update = () => {
    const { thumbSize, travel, overflow } = metrics();
    const offset = overflow
      ? Math.max(0, Math.min(1, viewport[position] / overflow)) * travel
      : 0;
    thumb.style[size] = `${thumbSize}px`;
    thumb.style.transform = `translate${horizontal ? "X" : "Y"}(${offset}px)`;
  };
  if (autoUpdate) on(viewport, "scroll", update);
  on(thumb, "pointerdown", (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    event.stopPropagation();
    drag = {
      pointer: event.pointerId,
      coordinate: event[coordinate],
      scroll: viewport[position],
    };
    thumb.setPointerCapture(event.pointerId);
    track.setAttribute("data-dragging", "");
  });
  on(thumb, "pointermove", (event) => {
    if (!drag || drag.pointer !== event.pointerId) return;
    const { travel, overflow } = metrics();
    if (travel > 0)
      viewport[position] =
        drag.scroll +
        ((event[coordinate] - drag.coordinate) * overflow) / travel;
  });
  const cancel = () => {
    if (drag && thumb.hasPointerCapture(drag.pointer))
      thumb.releasePointerCapture(drag.pointer);
    drag = null;
    track.removeAttribute("data-dragging");
  };
  for (const name of ["pointerup", "pointercancel", "lostpointercapture"])
    on(thumb, name, cancel);
  on(window, "blur", cancel);
  on(track, "pointerdown", (event) => {
    if (event.target !== track || event.button !== 0) return;
    event.preventDefault();
    const { thumbSize, travel, overflow } = metrics();
    const origin = track.getBoundingClientRect()[horizontal ? "left" : "top"];
    if (travel > 0)
      viewport[position] =
        ((event[coordinate] - origin - thumbSize / 2) / travel) * overflow;
  });
  if (autoUpdate) update();
  return {
    update,
    destroy: () => {
      cancel();
      abort.abort();
    },
  };
}
