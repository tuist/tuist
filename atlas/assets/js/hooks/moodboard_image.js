export default {
  mounted() {
    this.onError = () => { this.el.hidden = true }
    this.onLoad = () => { this.el.hidden = false }
    this.el.addEventListener("error", this.onError)
    this.el.addEventListener("load", this.onLoad)
    this.updated()
  },
  updated() {
    this.el.hidden = this.el.complete && this.el.naturalWidth === 0
  },
  destroyed() {
    this.el.removeEventListener("error", this.onError)
    this.el.removeEventListener("load", this.onLoad)
  },
}
