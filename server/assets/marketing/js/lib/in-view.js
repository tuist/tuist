/**
 * Runs `enter` when `el` scrolls into view (plus a margin) and `leave` when
 * it scrolls out, so a canvas animation loop only costs frames while it can
 * be seen. Returns a function that stops observing.
 *
 * `checkVisibility()` is not enough for this: it only reports display /
 * visibility / content-visibility, so an element far below the fold still
 * counts as visible and its loop keeps rendering every frame. On the home
 * page a dozen such loops shared the main thread with the ones on screen.
 */
export function whenInView(el, { enter, leave, rootMargin = "160px" }) {
  if (typeof IntersectionObserver === "undefined") {
    enter();
    return () => {};
  }
  let inView = false;
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting === inView) continue;
        inView = entry.isIntersecting;
        if (inView) enter();
        else leave();
      }
    },
    { rootMargin },
  );
  observer.observe(el);
  return () => {
    observer.disconnect();
    if (inView) leave();
  };
}
