export default {
  mounted() {
    this.copyToClipboard = (event) => {
      // Use currentTarget to get the element with the phx-hook, not the clicked child
      const value = event.currentTarget.dataset.clipboardValue;
      if (value) {
        navigator.clipboard.writeText(value);
      }
    };

    this.el.addEventListener("click", this.copyToClipboard);
  },

  destroyed() {
    if (this.copyToClipboard) {
      this.el.removeEventListener("click", this.copyToClipboard);
    }
  },
};
