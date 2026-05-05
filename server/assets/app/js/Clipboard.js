import { copyTextToClipboard } from "../../shared/js/clipboard.js";

export default {
  mounted() {
    this.copyToClipboard = (event) => {
      // Use currentTarget to get the element with the phx-hook, not the clicked child.
      const value = event.currentTarget.dataset.clipboardValue;
      if (!value) {
        return;
      }

      event.preventDefault();

      copyTextToClipboard(value, {
        container: this.el.closest("[role='dialog']"),
      }).catch((error) => {
        console.warn("Failed to copy text to clipboard", error);
      });
    };

    this.el.addEventListener("click", this.copyToClipboard);
  },

  destroyed() {
    if (this.copyToClipboard) {
      this.el.removeEventListener("click", this.copyToClipboard);
    }
  },
};
