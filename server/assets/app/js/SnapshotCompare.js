// Drives the snapshot review page's wipe and onion comparisons. One position
// (0–100) is the wipe's boundary between the baseline (left) and the new image
// (right), or the new image's opacity over the baseline. It is set with the
// range input or by dragging on the image, and only a CSS custom property
// changes, so the comparison stays local to the browser.
export default {
  mounted() {
    this.input = this.el.querySelector("input[type=range]");
    this.frame = this.el.querySelector("[data-part=compare-frame]");
    this.update = () => this.el.style.setProperty("--snapshot-compare-position", this.input.value);

    // The comparison is physically left to right, as its legend is, so the
    // pointer's offset maps directly to the position.
    this.drag = (event) => {
      const rect = this.frame.getBoundingClientRect();
      const position = ((event.clientX - rect.left) / rect.width) * 100;
      this.input.value = Math.round(Math.min(100, Math.max(0, position)));
      this.update();
    };
    this.pointerDown = (event) => {
      // Without this the browser starts a text selection or an image drag,
      // which highlights the images while the pointer moves.
      event.preventDefault();
      this.frame.setPointerCapture(event.pointerId);
      this.drag(event);
    };
    this.pointerMove = (event) => {
      if (this.frame.hasPointerCapture(event.pointerId)) this.drag(event);
    };

    this.input.addEventListener("input", this.update);
    this.frame.addEventListener("pointerdown", this.pointerDown);
    this.frame.addEventListener("pointermove", this.pointerMove);
    this.update();
  },

  updated() {
    this.update();
  },

  destroyed() {
    this.input.removeEventListener("input", this.update);
    this.frame.removeEventListener("pointerdown", this.pointerDown);
    this.frame.removeEventListener("pointermove", this.pointerMove);
  },
};
