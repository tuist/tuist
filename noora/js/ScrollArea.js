// Overlay scrollbar for a scrollable viewport. The native scrollbar is hidden
// (so it never reserves a gutter or shifts content) and replaced by an
// absolutely positioned track + thumb. The thumb is sized and moved from the
// viewport's scroll metrics, and supports dragging and track-click paging.
// The track only renders for fine pointers; touch scrolling is untouched.

const MIN_THUMB_HEIGHT = 24;

export default {
  mounted() {
    this.viewport = this.el.querySelector(':scope > [data-part="viewport"]');
    this.track = this.el.querySelector(':scope > [data-part="scrollbar"]');
    this.thumb = this.track?.querySelector('[data-part="thumb"]');
    if (!this.viewport || !this.track || !this.thumb) return;

    this.update = this.update.bind(this);
    this.onThumbDown = this.onThumbDown.bind(this);
    this.onThumbMove = this.onThumbMove.bind(this);
    this.onThumbUp = this.onThumbUp.bind(this);
    this.onTrackDown = this.onTrackDown.bind(this);
    this.onTrackWheel = this.onTrackWheel.bind(this);

    this.viewport.addEventListener("scroll", this.update, { passive: true });
    // Group expand/collapse animations change scrollHeight over time.
    this.viewport.addEventListener("animationend", this.update);
    this.thumb.addEventListener("pointerdown", this.onThumbDown);
    this.thumb.addEventListener("pointermove", this.onThumbMove);
    this.thumb.addEventListener("pointerup", this.onThumbUp);
    this.thumb.addEventListener("pointercancel", this.onThumbUp);
    this.track.addEventListener("pointerdown", this.onTrackDown);
    // The track overlays the viewport's edge and isn't itself scrollable, so
    // wheel events over it would fall through to the page scroll.
    this.track.addEventListener("wheel", this.onTrackWheel, { passive: false });

    this.resizeObserver = new ResizeObserver(this.update);
    this.resizeObserver.observe(this.el);
    this.resizeObserver.observe(this.viewport);
    this.mutationObserver = new MutationObserver(this.update);
    this.mutationObserver.observe(this.viewport, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["data-state", "hidden", "style"],
    });

    this.update();
  },

  updated() {
    this.update();
  },

  metrics() {
    const { scrollHeight, clientHeight, scrollTop } = this.viewport;
    const trackHeight = this.track.clientHeight;
    const thumbHeight = Math.max(
      (clientHeight / scrollHeight) * trackHeight,
      MIN_THUMB_HEIGHT,
    );
    return {
      maxScroll: scrollHeight - clientHeight,
      maxThumbY: trackHeight - thumbHeight,
      thumbHeight,
      scrollTop,
    };
  },

  update() {
    if (!this.viewport || !this.thumb) return;
    const { scrollHeight, clientHeight, scrollTop } = this.viewport;
    const scrollable = scrollHeight > clientHeight + 1;
    this.el.toggleAttribute("data-scrollable", scrollable);
    this.el.toggleAttribute(
      "data-at-end",
      !scrollable || scrollTop + clientHeight >= scrollHeight - 1,
    );
    if (!scrollable) return;

    const m = this.metrics();
    const y = m.maxScroll > 0 ? (m.scrollTop / m.maxScroll) * m.maxThumbY : 0;
    this.thumb.style.height = `${m.thumbHeight}px`;
    this.thumb.style.transform = `translateY(${y}px)`;
  },

  onThumbDown(event) {
    event.preventDefault();
    event.stopPropagation();
    this.thumb.setPointerCapture(event.pointerId);
    this.dragStartY = event.clientY;
    this.dragStartScroll = this.viewport.scrollTop;
    this.track.setAttribute("data-dragging", "");
  },

  onThumbMove(event) {
    if (!this.track.hasAttribute("data-dragging")) return;
    const m = this.metrics();
    if (m.maxThumbY <= 0) return;
    const delta = event.clientY - this.dragStartY;
    this.viewport.scrollTop =
      this.dragStartScroll + delta * (m.maxScroll / m.maxThumbY);
  },

  onThumbUp(event) {
    this.thumb.releasePointerCapture(event.pointerId);
    this.track.removeAttribute("data-dragging");
  },

  onTrackDown(event) {
    if (event.target !== this.track) return;
    const m = this.metrics();
    if (m.maxThumbY <= 0) return;
    const rect = this.track.getBoundingClientRect();
    const y = event.clientY - rect.top - m.thumbHeight / 2;
    this.viewport.scrollTop = (y / m.maxThumbY) * m.maxScroll;
  },

  onTrackWheel(event) {
    event.preventDefault();
    this.viewport.scrollTop += event.deltaY;
  },

  cleanup() {
    this.resizeObserver?.disconnect();
    this.mutationObserver?.disconnect();
    this.viewport?.removeEventListener("scroll", this.update);
    this.viewport?.removeEventListener("animationend", this.update);
    this.track?.removeEventListener("wheel", this.onTrackWheel);
  },

  beforeDestroy() {
    this.cleanup();
  },

  destroyed() {
    this.cleanup();
  },
};
