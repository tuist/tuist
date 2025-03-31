export default {
  mounted() {
    this.handleError = () => {
      this.el.src = this.el.dataset.fallbackSrc;
    };

    this.el.addEventListener("error", this.handleError);
  },

  destroyed() {
    if (this.handleError) {
      this.el.removeEventListener("error", this.handleError);
    }
  },
};
