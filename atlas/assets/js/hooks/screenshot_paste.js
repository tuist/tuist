// Captures image paste events on the host element (e.g. a form wrapping a
// textarea), reads pasted files as base64, and pushes a "screenshots_pasted"
// event to the LiveView. Also listens for a "set-note-body" server event so
// the LiveView can populate the textarea with an agent-drafted note while
// preserving its editability.
const ScreenshotPaste = {
  mounted() {
    this.onPaste = (event) => this.handlePaste(event)
    this.el.addEventListener("paste", this.onPaste)

    this.handleEvent("set-note-body", ({body}) => {
      const textarea = this.el.querySelector("textarea")
      if (!textarea) return
      textarea.value = body || ""
      textarea.dispatchEvent(new Event("input", {bubbles: true}))
      textarea.dispatchEvent(new Event("change", {bubbles: true}))
      textarea.focus()
    })
  },

  destroyed() {
    if (this.onPaste) this.el.removeEventListener("paste", this.onPaste)
  },

  handlePaste(event) {
    const clipboard = event.clipboardData || (event.originalEvent && event.originalEvent.clipboardData)
    if (!clipboard || !clipboard.items) return

    const files = Array.from(clipboard.items)
      .filter(item => item.kind === "file" && item.type && item.type.startsWith("image/"))
      .map(item => item.getAsFile())
      .filter(file => file)

    if (files.length === 0) return

    event.preventDefault()

    Promise.all(files.map(file => this.readFileAsBase64(file))).then(screenshots => {
      const readableScreenshots = screenshots.filter(screenshot => screenshot)
      if (readableScreenshots.length === 0) return

      this.pushEvent("screenshots_pasted", {screenshots: readableScreenshots})
    })
  },

  readFileAsBase64(file) {
    return new Promise(resolve => {
      const reader = new FileReader()
      reader.onload = () => {
        const result = reader.result || ""
        // result is a data URL: "data:<media-type>;base64,<data>"
        const commaIndex = result.indexOf(",")
        if (commaIndex === -1) {
          resolve(null)
          return
        }

        const meta = result.slice(0, commaIndex)
        const data = result.slice(commaIndex + 1)
        const mediaTypeMatch = meta.match(/^data:([^;]+);base64$/)
        const mediaType = mediaTypeMatch ? mediaTypeMatch[1] : file.type

        resolve({
          data,
          media_type: mediaType,
          name: file.name,
          size: file.size,
        })
      }
      reader.onerror = () => {
        // Silently drop; the user can retry.
        resolve(null)
      }
      reader.readAsDataURL(file)
    })
  },
}

export default ScreenshotPaste
