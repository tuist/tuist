export default {
  mounted() {
    this.copyToClipboard = (event) => {
      navigator.clipboard.writeText(event.target.dataset.clipboardValue);
    };

    this.el.addEventListener("click", this.copyToClipboard);
  },

  destroyed() {
    if (this.copyToClipboard) {
      this.el.removeEventListener("click", this.copyToClipboard);
    }
  },
};
