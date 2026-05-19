// Noora's table wraps every cell — including action cells — in an
// `<a phx-link="redirect">`. Without intervention, clicking the kebab
// or any of its dropdown items both fires the intended action *and*
// navigates the row, because LiveView's `bindNav` window handler
// matches the link and short-circuits the `phx-click` for the inner
// element (it calls `stopImmediatePropagation` after intercepting).
//
// We swallow every click that originates inside this wrapper to stop
// the navigation, and for clicks on menu items we manually push the
// item's `phx-click` so the row action still happens.
export default {
  mounted() {
    this.handler = (event) => {
      const item = event.target.closest('[data-part="item"]');

      if (item && item.hasAttribute("phx-click")) {
        const eventName = item.getAttribute("phx-click");
        const payload = phxValues(item);
        const confirm = item.getAttribute("data-confirm");

        if (confirm && !window.confirm(confirm)) {
          event.preventDefault();
          event.stopPropagation();
          return;
        }

        this.pushEvent(eventName, payload);
      }

      event.preventDefault();
      event.stopPropagation();
    };
    this.el.addEventListener("click", this.handler);
  },
  destroyed() {
    this.el.removeEventListener("click", this.handler);
  },
};

// Collect `phx-value-*` attributes from a node into a payload map, so
// we can replay them when manually pushing the event LiveView would
// otherwise have sent.
function phxValues(node) {
  const payload = {};
  for (const attr of node.attributes) {
    if (attr.name.startsWith("phx-value-")) {
      payload[attr.name.slice("phx-value-".length)] = attr.value;
    }
  }
  return payload;
}
