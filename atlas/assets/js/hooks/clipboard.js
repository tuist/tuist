import { copyTextToClipboard } from "../clipboard.js"

function flashCopied(button) {
  button.setAttribute("data-copied", "")
  const originalLabel = button.getAttribute("aria-label")
  button.setAttribute("aria-label", "Copied")
  if (button._copiedTimeout) clearTimeout(button._copiedTimeout)
  button._copiedTimeout = setTimeout(() => {
    button.removeAttribute("data-copied")
    if (originalLabel) button.setAttribute("aria-label", originalLabel)
  }, 2000)
}

export default {
  mounted() {
    this.copyToClipboard = (event) => {
      const button = event.currentTarget
      const value = button.dataset.clipboardValue
      if (!value) return
      event.preventDefault()

      copyTextToClipboard(value, {
        container: this.el.closest("[role='dialog']"),
      })
        .then(() => flashCopied(button))
        .catch((error) => {
          console.warn("Failed to copy text to clipboard", error)
        })
    }

    this.el.addEventListener("click", this.copyToClipboard)
  },

  destroyed() {
    if (this.copyToClipboard) {
      this.el.removeEventListener("click", this.copyToClipboard)
    }
  },
}
