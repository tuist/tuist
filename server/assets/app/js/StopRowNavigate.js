// Noora's table wraps every cell — including action cells — in an
// `<a phx-link="redirect">`. Without intervention, clicking a kebab
// inside such a cell both opens the dropdown *and* navigates the row,
// because the browser follows the link's `href` and LiveView also runs
// its own window-level click handler.
//
// Zag uses `pointerdown` to open the menu, so by the time the click
// bubbles up to this wrapper the dropdown is already open. We then:
//   - `preventDefault` to cancel the browser's follow-the-link action,
//   - `stopPropagation` to keep the click from reaching LiveView's
//     window-level link handler (`LiveSocket.bindNav`).
export default {
  mounted() {
    this.handler = (event) => {
      event.preventDefault();
      event.stopPropagation();
    };
    this.el.addEventListener("click", this.handler);
  },
  destroyed() {
    this.el.removeEventListener("click", this.handler);
  },
};
