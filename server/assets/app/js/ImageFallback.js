export default {
  mounted() {
    let fallbackSrc = this.el.src;
    let handledError = false;
    this.handleError = () => {
      this.el.src = fallbackSrc;
      handledError = true;
      this.el.removeEventListener("error", this.handleError);
    };

    this.el.addEventListener("error", this.handleError);

    if (this.el.dataset.imageSrc) {
      this.el.src = this.el.dataset.imageSrc;
    }
  },

  destroyed() {
    if (this.handleError) {
      this.el.removeEventListener("error", this.handleError);
    }
  },
};
