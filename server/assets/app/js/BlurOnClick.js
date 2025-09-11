export default {
  mounted() {
    this.el.addEventListener("click", () => {
      this.el.blur();
    });
  },
};
