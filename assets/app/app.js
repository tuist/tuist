// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "./js/vendor/topbar.js";
import "./js/Chart.js";
import "./js/Stack.js";
import * as NooraComponents from "../_noora/noora.js";
import "./app.css";
import ThemeSwitcher, { observeThemeChanges } from "./js/ThemeSwitcher.js";
import ImageFallback from "./js/ImageFallback.js";
import DeeplinkValidation from "./js/DeeplinkValidation.js";
import Clipboard from "./js/Clipboard.js";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let cspNonce = document.querySelector("meta[name='csp-nonce']").getAttribute("content");

let Hooks = {};
Hooks.ImageFallback = ImageFallback;
Hooks.Clipboard = Clipboard;
Hooks.DeeplinkValidation = DeeplinkValidation;
Hooks.Chart = {
  mounted() {
    this.render();
  },

  updated() {
    this.render();
  },

  render() {
    this.el.formatter = this.el.dataset.formatter;

    const data = JSON.parse(this.el.dataset.series);
    const labels = JSON.parse(this.el.dataset.labels);

    this.el.data = {
      name: this.el.dataset.name,
      data: data,
      labels: labels,
    };

    if (this.el.dataset.config) {
      const config = JSON.parse(this.el.dataset.config);
      this.el.totalLabel = config.totalLabel;
      if (config.colors) {
        this.el.colors = config.colors.map((color) => cssvar(color));
      }

      if (config.stroke) {
        this.el.stroke = {
          ...config.stroke,
          colors: config.stroke.colors.map((color) => cssvar(color)),
        };
      }
    }

    this.el.render();
  },
};

observeThemeChanges();
Hooks.ThemeSwitcher = ThemeSwitcher;
Object.keys(NooraComponents).forEach((key) => {
  Hooks[key] = NooraComponents[key];
});

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken, _csp_nonce: cspNonce },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({
  barColors: { 0: "#29d" },
  shadowColor: "rgba(0, 0, 0, .3)",
});
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// Analytics
window.addEventListener("phx:navigate", (info) => {
  if (globalThis.analyticsEnabled) {
    // https://hexdocs.pm/phoenix_live_view/js-interop.html#live-navigation-events
    posthog.capture("$pageview");
  }
});

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// Server-triggered `js-exec` events allow executing a server-declared
// %Phoenix.LiveView.JS{} action declared on a given element attribute.
window.addEventListener("phx:js-exec", ({ detail }) => {
  document.querySelectorAll(detail.to).forEach((el) => {
    liveSocket.execJS(el, el.getAttribute(detail.attr));
  });
});
