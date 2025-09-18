export default {
  mounted() {
    this.handleScrollToElement = (event) => {
      if (event.detail.id === this.el.id) {
        this.el.scrollIntoView({
          behavior: "smooth",
          block: "start",
        });
      }
    };
    window.addEventListener("phx:scroll-to-element", this.handleScrollToElement);
  },

  destroyed() {
    window.removeEventListener("phx:scroll-to-element", this.handleScrollToElement);
  },
};
