const SearchPalette = {
  mounted() {
    this._isOpen = false
    this._sync()

    this._input = () => this.el.querySelector("input")

    this._onKeyDown = (event) => {
      const isMeta = event.metaKey || event.ctrlKey

      if (isMeta && (event.key === "k" || event.key === "K")) {
        event.preventDefault()
        if (this._isOpen) {
          this._close()
        } else {
          this._open()
        }
        return
      }

      if (event.key === "Escape" && this._isOpen) {
        event.preventDefault()
        this._close()
      }
    }

    this._onClick = (event) => {
      if (event.target.closest("[data-action='close']")) {
        this._close()
        return
      }

      if (event.target.closest("[data-result-link]")) {
        this._close()
      }
    }

    window.addEventListener("keydown", this._onKeyDown)
    this.el.addEventListener("click", this._onClick)
  },

  updated() {
    this._sync()
  },

  destroyed() {
    window.removeEventListener("keydown", this._onKeyDown)
  },

  _sync() {
    this.el.dataset.open = this._isOpen ? "true" : "false"
  },

  _open() {
    this._isOpen = true
    this._sync()
    const input = this._input()
    if (!input) return
    requestAnimationFrame(() => {
      input.focus()
      input.select()
    })
  },

  _close() {
    this._isOpen = false
    this._sync()
    const input = this._input()
    if (input) input.blur()
  },
}

export default SearchPalette
