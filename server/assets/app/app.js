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
import Noora from "noora";
import "./app.css";
import ThemeSwitcher, { observeThemeChanges } from "./js/ThemeSwitcher.js";
import ImageFallback from "./js/ImageFallback.js";
import DeeplinkValidation from "./js/DeeplinkValidation.js";
import Clipboard from "./js/Clipboard.js";
import BundleSizeSunburstChartLegend from "./js/BundleSizeSunburstChartLegend.js";
import VideoPlayer from "./js/VideoPlayer.js";
import TimelineSeek from "./js/TimelineSeek.js";
import BlurOnClick from "./js/BlurOnClick.js";
import ScrollIntoView from "./js/ScrollIntoView.js";
import StopPropagationOnDrag from "./js/StopPropagationOnDrag.js";
import { getUserTimezone } from "./js/UserTimezone.js";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let cspNonce = document.querySelector("meta[name='csp-nonce']").getAttribute("content");

let Hooks = {};
Hooks.ImageFallback = ImageFallback;
Hooks.Clipboard = Clipboard;
Hooks.DeeplinkValidation = DeeplinkValidation;
Hooks.BundleSizeSunburstChartLegend = BundleSizeSunburstChartLegend;
Hooks.VideoPlayer = VideoPlayer;
Hooks.TimelineSeek = TimelineSeek;
Hooks.BlurOnClick = BlurOnClick;
Hooks.ScrollIntoView = ScrollIntoView;
Hooks.StopPropagationOnDrag = StopPropagationOnDrag;

observeThemeChanges();
Hooks.ThemeSwitcher = ThemeSwitcher;

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {
    _csrf_token: csrfToken,
    _csp_nonce: cspNonce,
    user_timezone: getUserTimezone(),
  },
  hooks: { ...Hooks, ...Noora.Hooks },
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
  if (globalThis.analytics.enabled) {
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
