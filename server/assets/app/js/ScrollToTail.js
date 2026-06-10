const defaultBottomThreshold = 24;

export default {
  mounted() {
    this.hasPinnedTail = false;
    this.pinTail();
  },

  beforeUpdate() {
    this.wasNearBottom = this.distanceFromBottom() <= this.bottomThreshold();
    this.previousScrollHeight = this.el.scrollHeight;
    this.previousScrollTop = this.el.scrollTop;
    this.previousFirstItemId = this.firstItemId();
  },

  updated() {
    window.requestAnimationFrame(() => {
      if (!this.isEnabled()) return;

      const firstItemId = this.firstItemId();
      const prependedItems =
        this.previousFirstItemId && firstItemId && firstItemId !== this.previousFirstItemId;

      if (!this.hasPinnedTail || this.wasNearBottom) {
        this.pinTail();
      } else if (prependedItems) {
        this.el.scrollTop =
          this.previousScrollTop + (this.el.scrollHeight - this.previousScrollHeight);
      }
    });
  },

  pinTail() {
    window.requestAnimationFrame(() => {
      if (!this.isEnabled()) return;

      this.el.scrollTop = this.el.scrollHeight;
      this.hasPinnedTail = true;
    });
  },

  distanceFromBottom() {
    return this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight;
  },

  firstItemId() {
    const selector = this.el.dataset.scrollToTailItemSelector;

    if (!selector) return null;

    return this.el.querySelector(selector)?.id;
  },

  bottomThreshold() {
    const threshold = Number.parseInt(this.el.dataset.scrollToTailBottomThreshold, 10);

    return Number.isNaN(threshold) ? defaultBottomThreshold : threshold;
  },

  isEnabled() {
    return this.el.dataset.scrollToTailActive !== "false" && this.el.offsetParent !== null;
  },
};
