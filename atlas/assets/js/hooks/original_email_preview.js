const OriginalEmailPreview = {
  mounted() {
    this.resize = this.resize.bind(this)
    this.el.addEventListener("load", this.resize)
    this.resize()
  },

  destroyed() {
    this.el.removeEventListener("load", this.resize)
    this.resizeObserver?.disconnect()
  },

  resize() {
    const document = this.el.contentDocument

    if (!document?.documentElement) return

    this.resizeObserver?.disconnect()
    this.resizeObserver = new ResizeObserver(() => this.setHeight())
    this.resizeObserver.observe(document.documentElement)

    if (document.body) {
      this.resizeObserver.observe(document.body)
    }

    this.setHeight()
  },

  setHeight() {
    const document = this.el.contentDocument

    if (!document?.documentElement) return

    const {body, documentElement} = document
    const height = Math.max(
      documentElement.scrollHeight,
      documentElement.offsetHeight,
      body?.scrollHeight ?? 0,
      body?.offsetHeight ?? 0,
    )

    this.el.style.height = `${height}px`
  },
}

export default OriginalEmailPreview
