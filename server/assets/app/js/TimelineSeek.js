export default {
  mounted() {
    this.el.addEventListener("click", (e) => {
      // Don't handle clicks on step items - they have their own phx-click handlers
      if (e.target.closest('[data-part="step-item"]')) {
        return;
      }

      const playheadArea = document.querySelector("#playhead-area");
      const rect = this.el.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const width = playheadArea.clientWidth;
      const percentage = x / width;
      const duration = parseFloat(this.el.dataset.duration || "120");
      const seekTime = percentage * duration;

      this.pushEvent("seek", { time: seekTime.toString() });
    });
  }
};
