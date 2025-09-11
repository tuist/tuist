export default {
  mounted() {
    this.el.addEventListener("click", (e) => {
      // Don't handle clicks when clicking on an element with phx-click as that should take precedence
      if (e.target.closest("[phx-click]")) {
        return;
      }

      const playheadArea = document.querySelector("#playhead-area");
      const rect = this.el.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const width = playheadArea.clientWidth;
      const percentage = x / width;
      const duration = parseFloat(this.el.dataset.duration);

      this.pushEvent("seek", { time: percentage * duration });
    });
  },
};
