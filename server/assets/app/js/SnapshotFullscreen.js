// Keyboard for the snapshot review's full-screen viewer: the arrow keys step
// to the previous or next image and Escape closes it, by following the
// viewer's own links. Keys typed into a control, such as the wipe's slider,
// stay with that control.
export default {
  mounted() {
    this.keydown = (event) => {
      if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) return;
      if (event.target.closest("input, textarea, select, [contenteditable]")) return;

      const part = { ArrowLeft: "previous", ArrowRight: "next", Escape: "close" }[event.key];
      const link = part && this.el.querySelector(`[data-part=${part}]:not([aria-disabled=true])`);
      if (!link) return;

      event.preventDefault();
      link.click();
    };
    window.addEventListener("keydown", this.keydown);
    this.el.focus();
  },

  destroyed() {
    window.removeEventListener("keydown", this.keydown);
  },
};
