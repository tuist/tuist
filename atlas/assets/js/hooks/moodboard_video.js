export default {
  mounted() {
    this.onError = () => { this.el.hidden = true }
    this.onLoaded = () => { this.el.hidden = false }
    this.el.addEventListener("error", this.onError)
    this.el.addEventListener("loadedmetadata", this.onLoaded)
    this.updated()
  },
  updated() {
    this.el.hidden = !!this.el.error
  },
  destroyed() {
    this.el.removeEventListener("error", this.onError)
    this.el.removeEventListener("loadedmetadata", this.onLoaded)
  },
}
