// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { Hooks } from "./js/hooks.js";
import Noora from "noora";
import "./marketing.css";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let cspNonce = document.querySelector("meta[name='csp-nonce']").getAttribute("content");
// Keep this aligned with nginx.ingress.kubernetes.io/proxy-connect-timeout.
const liveSocketFallbackMs = 10000;

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: liveSocketFallbackMs,
  // Join/push timeout (default 10s). In dev every dynamic request pays a
  // multi-second code-reloader pass under a global lock, so the first
  // join of a page load can queue 10-25s behind the page's own requests;
  // at the default timeout the client gives up, error-loops, and
  // force-reloads the page, leaving every canvas hook unmounted. 30s lets
  // the join ride out the queue (production joins reply in milliseconds,
  // so the longer ceiling only matters under load, where waiting beats a
  // reload storm anyway).
  timeout: 30000,
  params: { _csrf_token: csrfToken, _csp_nonce: cspNonce },
  hooks: { ...Noora.Hooks, ...Hooks },
});
liveSocket.connect();

// Analytics
window.addEventListener("phx:navigate", (info) => {
  if (globalThis.analytics.enabled) {
    // https://hexdocs.pm/phoenix_live_view/js-interop.html#live-navigation-events
    posthog.capture("$pageview");
  }
});

window.liveSocket = liveSocket;

// Server-triggered `js-exec` events allow executing a server-declared
// %Phoenix.LiveView.JS{} action declared on a given element attribute.
window.addEventListener("phx:js-exec", ({ detail }) => {
  document.querySelectorAll(detail.to).forEach((el) => {
    liveSocket.execJS(el, el.getAttribute(detail.attr));
  });
});
