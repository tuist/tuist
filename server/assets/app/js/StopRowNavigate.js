// Noora's table wraps every cell — including action cells — in an
// `<a phx-link="redirect">`. Without intervention, clicking a kebab
// inside such a cell both opens the dropdown *and* navigates the row.
//
// LiveView binds its link handler on `window` in the bubble phase
// (see `LiveSocket.bindNav` in phoenix_live_view), so swallowing the
// click on our wrapper in the bubble phase keeps the event from
// reaching LiveView. By that point the click has already passed
// through the target (Zag's onClick on the trigger), so the menu
// opens normally.
export default {
  mounted() {
    this.handler = (event) => {
      event.stopPropagation();
    };
    this.el.addEventListener("click", this.handler);
  },
  destroyed() {
    this.el.removeEventListener("click", this.handler);
  },
};
