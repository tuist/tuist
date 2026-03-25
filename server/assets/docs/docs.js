import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../app/js/vendor/topbar.js";
import Noora from "noora";
import DocsContentHook from "./hooks/docs-content-hook.js";
import DocsInstallTabsHook from "./hooks/docs-install-tabs-hook.js";

import "./docs.css";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let cspNonce = document.querySelector("meta[name='csp-nonce']").getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken, _csp_nonce: cspNonce },
  hooks: {
    ...Noora.Hooks,
    DocsContent: DocsContentHook,
    DocsInstallTabs: DocsInstallTabsHook,
  },
});

topbar.config({
  barColors: { 0: "#29d" },
  shadowColor: "rgba(0, 0, 0, .3)",
});
window.addEventListener("phx:page-loading-start", (_info) => {
  topbar.show(300);
  document.body.removeAttribute("data-sidebar-open");
  document.getElementById("docs-sidebar")?.removeAttribute("data-mobile-open");
});
window.addEventListener("phx:page-loading-stop", (_info) => {
  topbar.hide();
  window.scrollTo(0, 0);
  document.body.removeAttribute("data-sidebar-open");
  document.getElementById("docs-sidebar")?.removeAttribute("data-mobile-open");
});

liveSocket.connect();

window.addEventListener("phx:navigate", () => {
  if (globalThis.analytics.enabled) {
    posthog.capture("$pageview");
  }
});

window.liveSocket = liveSocket;

window.addEventListener("phx:js-exec", ({ detail }) => {
  document.querySelectorAll(detail.to).forEach((el) => {
    liveSocket.execJS(el, el.getAttribute(detail.attr));
  });
});
