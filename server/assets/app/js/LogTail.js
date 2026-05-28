// Keeps the runner logs viewport pinned to the bottom (the latest
// line), like a terminal tail:
//
//   - scrolls to the bottom on mount and whenever the Logs tab becomes
//     active (tracked via the element's `data-active` attribute);
//   - on new lines (live tail), scrolls only if the user is already at
//     the bottom — so manually scrolling up, or clicking "Load older
//     logs" (which prepends), isn't yanked back down.
const NEAR_BOTTOM_THRESHOLD_PX = 40;

export default {
  mounted() {
    this.pinned = true;

    if (this.isActive()) {
      this.scrollToBottom();
    }
  },

  beforeUpdate() {
    this.wasActive = this.isActive();
    this.pinned = this.isNearBottom();
  },

  updated() {
    const becameActive = this.isActive() && !this.wasActive;

    if (this.isActive() && (becameActive || this.pinned)) {
      this.scrollToBottom();
    }
  },

  isActive() {
    return this.el.dataset.active === "true";
  },

  isNearBottom() {
    const { scrollHeight, scrollTop, clientHeight } = this.el;
    return scrollHeight - scrollTop - clientHeight < NEAR_BOTTOM_THRESHOLD_PX;
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};
