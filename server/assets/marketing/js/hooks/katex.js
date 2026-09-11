// KaTeX is loaded on demand: only blog posts with math mount this hook, and
// the library is ~260 KB minified that every other page would otherwise
// download and parse. The dynamic import becomes its own chunk.
let katexModule = null;
function loadKatex() {
  if (!katexModule) katexModule = import("katex").then((m) => m.default || m);
  return katexModule;
}

const KaTeX = {
  mounted() {
    this.render();
  },

  updated() {
    this.render();
  },

  render() {
    const el = this.el;
    loadKatex().then((katex) => {
      if (!el.isConnected) return;
      katex.render(el.dataset.latex, el, {
        displayMode: el.dataset.mathStyle === "display",
        throwOnError: false,
        trust: false,
      });
    });
  },
};

export { KaTeX };
