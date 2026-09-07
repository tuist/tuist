// Chromium/Firefox expose trackpad pinches as Ctrl+wheel; WebKit also exposes GestureEvents.
export function bindPinchZoom(element, zoom, signal) {
  const options = { passive: false, signal };
  let gestureScale = null;
  element.addEventListener(
    "wheel",
    (event) => {
      if (!event.ctrlKey) return;
      event.preventDefault();
      if (gestureScale !== null) return;
      const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? element.clientHeight : 1;
      zoom(Math.exp(Math.max(-100, Math.min(100, event.deltaY * unit)) * 0.01), event);
    },
    options,
  );
  element.addEventListener(
    "gesturestart",
    (event) => {
      event.preventDefault();
      gestureScale = event.scale;
    },
    options,
  );
  element.addEventListener(
    "gesturechange",
    (event) => {
      event.preventDefault();
      if (gestureScale === null || !(event.scale > 0)) return;
      zoom(gestureScale / event.scale, event);
      gestureScale = event.scale;
    },
    options,
  );
  element.addEventListener(
    "gestureend",
    (event) => {
      event.preventDefault();
      gestureScale = null;
    },
    options,
  );
}
