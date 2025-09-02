export default {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const rect = this.el.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const width = rect.width;
      const percentage = x / width;
      const duration = parseFloat(this.el.dataset.duration || "120");
      const seekTime = percentage * duration;
      
      this.pushEvent("seek", { time: seekTime.toString() });
    });
  }
};