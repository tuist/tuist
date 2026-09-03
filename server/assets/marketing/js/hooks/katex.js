import katex from "katex";

const KaTeX = {
  mounted() {
    this.render();
  },

  updated() {
    this.render();
  },

  render() {
    katex.render(this.el.dataset.latex, this.el, {
      displayMode: this.el.dataset.mathStyle === "display",
      throwOnError: false,
      trust: false,
    });
  },
};

export { KaTeX };
