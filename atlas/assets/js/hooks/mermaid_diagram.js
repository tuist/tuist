const MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.esm.min.mjs"

let mermaidPromise = null
let renderSequence = 0

function loadMermaid() {
  if (!mermaidPromise) {
    mermaidPromise = import(MERMAID_URL)
      .then((module) => module.default)
      .catch((error) => {
        mermaidPromise = null
        throw error
      })
  }
  return mermaidPromise
}

function prefersDark() {
  const theme = document.documentElement.dataset.theme
  if (theme === "dark" || theme === "light") return theme === "dark"
  return window.matchMedia("(prefers-color-scheme: dark)").matches
}

export default {
  mounted() {
    this.source = this.el.querySelector("[data-part='mermaid-source']").textContent
    this.diagram = this.el.querySelector("[data-part='mermaid-diagram']")
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.onSchemeChange = () => this.render()
    this.media.addEventListener("change", this.onSchemeChange)
    this.render()
  },

  destroyed() {
    this.media.removeEventListener("change", this.onSchemeChange)
  },

  async render() {
    try {
      const mermaid = await loadMermaid()
      if (!this.el.isConnected) return

      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        theme: prefersDark() ? "dark" : "default",
      })

      if (!(await mermaid.parse(this.source, {suppressErrors: true}))) {
        this.el.dataset.state = "error"
        return
      }

      renderSequence += 1
      const {svg} = await mermaid.render(`mermaid-svg-${renderSequence}`, this.source)
      if (!this.el.isConnected) return

      this.diagram.innerHTML = svg
      this.el.dataset.state = "rendered"
    } catch (error) {
      console.error("Failed to render Mermaid diagram", error)
      this.el.dataset.state = "error"
    }
  },
}
