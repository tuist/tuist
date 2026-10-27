import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const Hooks = {
  NooraWebComponentExample: {
    mounted() {
      this.applyProperties();
    },
    updated() {
      this.applyProperties();
    },
    applyProperties() {
      const assignments = JSON.parse(this.el.dataset.propertyAssignments);

      for (const [selector, properties] of Object.entries(assignments)) {
        const element = this.el.querySelector(selector);
        if (element) Object.assign(element, properties);
      }
    },
  },
};

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
});

liveSocket.connect();

window.liveSocket = liveSocket;
