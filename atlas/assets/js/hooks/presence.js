export default {
  mounted() {
    this.visibilityChanged = () => {
      this.pushEvent("presence_visibility", {visible: document.visibilityState === "visible"})
    }
    document.addEventListener("visibilitychange", this.visibilityChanged)
    this.visibilityChanged()
  },
  reconnected() { this.visibilityChanged() },
  destroyed() { document.removeEventListener("visibilitychange", this.visibilityChanged) },
}
