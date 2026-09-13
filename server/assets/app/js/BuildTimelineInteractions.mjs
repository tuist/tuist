export function debounce(callback, delay, signal) {
  let timer;
  const cancel = () => clearTimeout(timer);
  signal.addEventListener("abort", cancel, { once: true });
  return (...args) => {
    cancel();
    if (!signal.aborted) timer = setTimeout(() => callback(...args), delay);
  };
}

export function hitInLane(rects, x, y) {
  if (!rects) return;
  let low = 0;
  let high = rects.length;
  while (low < high) {
    const mid = (low + high) >>> 1;
    if (rects[mid].right < x) low = mid + 1;
    else high = mid;
  }
  const rect = rects[low];
  if (rect && x >= rect.left && y >= rect.top && y <= rect.bottom) return rect.event;
}
