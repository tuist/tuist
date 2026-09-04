// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/tuist";
import { Hooks } from "./js/hooks.js";
import { initAnalytics } from "../shared/js/analytics.js";
import Noora from "noora";
import "katex/dist/katex.min.css";
import "./marketing.css";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let cspNonce = document.querySelector("meta[name='csp-nonce']").getAttribute("content");
// Keep this aligned with nginx.ingress.kubernetes.io/proxy-connect-timeout.
const liveSocketFallbackMs = 10000;

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: liveSocketFallbackMs,
  params: { _csrf_token: csrfToken, _csp_nonce: cspNonce },
  hooks: { ...Noora.Hooks, ...Hooks, ...colocatedHooks },
});
liveSocket.connect();

initAnalytics();

window.liveSocket = liveSocket;

// Server-triggered `js-exec` events allow executing a server-declared
// %Phoenix.LiveView.JS{} action declared on a given element attribute.
window.addEventListener("phx:js-exec", ({ detail }) => {
  document.querySelectorAll(detail.to).forEach((el) => {
    liveSocket.execJS(el, el.getAttribute(detail.attr));
  });
});
