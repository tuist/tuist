/**
 * Submits the hook's <form> on Cmd/Ctrl + Enter, with focus anywhere
 * inside the form (textarea, a button, etc.). Attach with phx-hook on a
 * <form> that has a phx-submit; requestSubmit() runs the same path as
 * the submit button.
 */
export default {
  mounted() {
    this.onKeydown = (event) => {
      if (event.key !== "Enter" || (!event.metaKey && !event.ctrlKey)) return;
      event.preventDefault();
      this.el.requestSubmit();
    };

    this.el.addEventListener("keydown", this.onKeydown);
  },

  destroyed() {
    if (this.onKeydown) this.el.removeEventListener("keydown", this.onKeydown);
  },
};
