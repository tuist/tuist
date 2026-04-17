function waitForMermaid() {
  return new Promise((resolve) => {
    if (window.mermaid) {
      resolve(window.mermaid);
      return;
    }
    const check = () => {
      if (window.mermaid) {
        resolve(window.mermaid);
      } else {
        setTimeout(check, 30);
      }
    };
    check();
  });
}

function themeVariables() {
  return typeof window.mermaidThemeVariables === "function" ? window.mermaidThemeVariables() : {};
}

const MermaidDiagramHook = {
  async mounted() {
    if (this.el.dataset.mermaidSource === undefined) {
      this.el.dataset.mermaidSource = this.el.textContent.trim();
    }

    const mermaid = await waitForMermaid();
    if (!this.el.isConnected) return;

    this.mermaid = mermaid;
    this.renderDiagram();

    this.themeListener = () => this.renderDiagram();
    window.addEventListener("changed-preferred-theme", this.themeListener);
  },

  destroyed() {
    if (this.themeListener) {
      window.removeEventListener("changed-preferred-theme", this.themeListener);
      this.themeListener = null;
    }
  },

  renderDiagram() {
    if (!this.mermaid || !this.el.isConnected) return;
    this.el.textContent = this.el.dataset.mermaidSource;
    this.el.removeAttribute("data-processed");
    this.mermaid.initialize({
      startOnLoad: false,
      securityLevel: "loose",
      theme: "base",
      themeVariables: themeVariables(),
    });
    this.mermaid.run({ nodes: [this.el] });
  },
};

export default MermaidDiagramHook;
