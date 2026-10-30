import {highlight} from "../../vendor/highlight"

const MAX_SOURCE_BYTES = 65_536
const MAX_HIGHLIGHT_LENGTH = 524_288

export function highlightSource(source, language) {
  if (!["json", "javascript"].includes(language) || source.length > MAX_SOURCE_BYTES ||
      new TextEncoder().encode(source).length > MAX_SOURCE_BYTES) return null
  try {
    const html = highlight(source, language)
    return html.length <= MAX_HIGHLIGHT_LENGTH ? html : null
  } catch {
    return null
  }
}

export default {
  mounted() {
    this.textarea = this.el.querySelector("textarea")
    this.mirror = this.el.querySelector("[data-part=code-editor-highlight]")
    this.code = this.mirror.querySelector("code")
    this.onInput = () => this.scheduleRefresh()
    this.onScroll = () => this.syncScroll()
    this.onCompositionStart = () => {
      this.composing = true
      this.el.dataset.enhanced = "false"
    }
    this.onCompositionEnd = () => {
      this.composing = false
      this.scheduleRefresh()
    }
    this.textarea.addEventListener("input", this.onInput)
    this.textarea.addEventListener("scroll", this.onScroll)
    this.textarea.addEventListener("compositionstart", this.onCompositionStart)
    this.textarea.addEventListener("compositionend", this.onCompositionEnd)
    this.textarea.form?.addEventListener("reset", this.onInput)
    this.observer = new ResizeObserver(() => this.syncViewport())
    this.observer.observe(this.textarea)
    this.observer.observe(this.el)
    this.refresh()
  },

  updated() {
    // Read the actual native input, not a potentially stale server echo while typing.
    this.refresh()
  },

  scheduleRefresh() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.refresh()
    })
  },

  refresh() {
    const value = this.textarea.value
    const language = this.el.dataset.language
    if (value !== this.value || language !== this.language) {
      this.value = value
      this.language = language
      const html = highlightSource(value, language)
      this.highlighted = html !== null
      if (this.highlighted) {
        // Only the pinned highlighter's escaped output becomes HTML, never raw source.
        this.code.innerHTML = html
        this.code.querySelectorAll("[class]").forEach(token => {
          token.dataset.token = token.className
          token.removeAttribute("class")
        })
        if (value.endsWith("\n")) this.code.append(document.createTextNode(" "))
      } else {
        this.code.textContent = ""
      }
    }
    this.syncViewport()
  },

  syncViewport() {
    const root = this.el.getBoundingClientRect()
    const input = this.textarea.getBoundingClientRect()
    const scaleX = root.width / this.el.offsetWidth || 1
    const scaleY = root.height / this.el.offsetHeight || 1
    const style = getComputedStyle(this.textarea)
    Object.assign(this.mirror.style, {
      left: `${(input.left - root.left) / scaleX + this.textarea.clientLeft}px`,
      top: `${(input.top - root.top) / scaleY + this.textarea.clientTop}px`,
      width: `${this.textarea.clientWidth}px`,
      height: `${this.textarea.clientHeight}px`,
      font: style.font,
      padding: style.padding,
      letterSpacing: style.letterSpacing,
      wordSpacing: style.wordSpacing,
      textIndent: style.textIndent,
    })
    this.el.dataset.enhanced = String(Boolean(this.highlighted && !this.composing && this.textarea.clientWidth > 0))
    this.syncScroll()
  },

  syncScroll() {
    this.mirror.scrollTop = this.textarea.scrollTop
    this.mirror.scrollLeft = this.textarea.scrollLeft
  },

  destroyed() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.observer.disconnect()
    this.textarea.removeEventListener("input", this.onInput)
    this.textarea.removeEventListener("scroll", this.onScroll)
    this.textarea.removeEventListener("compositionstart", this.onCompositionStart)
    this.textarea.removeEventListener("compositionend", this.onCompositionEnd)
    this.textarea.form?.removeEventListener("reset", this.onInput)
    delete this.el.dataset.enhanced
  },
}
