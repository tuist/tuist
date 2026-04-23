const MERMAID_LOAD_RETRY_MS = 30;
const MERMAID_LOAD_TIMEOUT_MS = 5000;

function abortError() {
  const error = new Error("Mermaid load aborted");
  error.name = "AbortError";
  return error;
}

function waitForMermaid({ signal, timeoutMs = MERMAID_LOAD_TIMEOUT_MS } = {}) {
  return new Promise((resolve, reject) => {
    if (window.mermaid) {
      resolve(window.mermaid);
      return;
    }

    if (signal?.aborted) {
      reject(abortError());
      return;
    }

    let retryTimeoutId = null;
    let timeoutId = null;

    const cleanup = () => {
      if (retryTimeoutId !== null) {
        clearTimeout(retryTimeoutId);
      }

      if (timeoutId !== null) {
        clearTimeout(timeoutId);
      }

      signal?.removeEventListener("abort", onAbort);
    };

    const onAbort = () => {
      cleanup();
      reject(abortError());
    };

    const check = () => {
      if (signal?.aborted) {
        onAbort();
        return;
      }

      if (window.mermaid) {
        cleanup();
        resolve(window.mermaid);
        return;
      }

      retryTimeoutId = window.setTimeout(check, MERMAID_LOAD_RETRY_MS);
    };

    signal?.addEventListener("abort", onAbort, { once: true });
    timeoutId = window.setTimeout(() => {
      cleanup();
      reject(new Error(`Timed out waiting for Mermaid to load after ${timeoutMs}ms`));
    }, timeoutMs);

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

    this.mermaidAbortController = new AbortController();

    let mermaid;
    try {
      mermaid = await waitForMermaid({ signal: this.mermaidAbortController.signal });
    } catch (error) {
      if (error.name !== "AbortError") {
        console.error("Failed to load Mermaid:", error);
      }
      return;
    }

    if (!this.el.isConnected) return;

    this.mermaid = mermaid;
    this.renderDiagram();

    this.themeListener = () => this.renderDiagram();
    window.addEventListener("changed-preferred-theme", this.themeListener);
  },

  destroyed() {
    if (this.mermaidAbortController) {
      this.mermaidAbortController.abort();
      this.mermaidAbortController = null;
    }

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
