// Noora's table wraps every cell — including action cells — in an
// `<a phx-link="redirect">`. Without intervention, clicking a kebab
// inside such a cell both opens the dropdown *and* navigates the row.
// Zag opens the menu on `pointerdown`, so by the time the trailing
// `click` arrives the menu is already up. We swallow that click in
// the capture phase so it never reaches LiveView's document-level
// link handler (which would redirect) or Zag's own click handler on
// the trigger (which would toggle the menu back closed).
export default {
  mounted() {
    this.handler = (event) => {
      event.preventDefault();
      event.stopPropagation();
    };
    this.el.addEventListener("click", this.handler, true);
  },
  destroyed() {
    this.el.removeEventListener("click", this.handler, true);
  },
};
