import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import Noora from "noora";
import DocsContentHook from "./hooks/docs-content-hook.js";
import DocsInstallTabsHook from "./hooks/docs-install-tabs-hook.js";
import DocsActivePageHook from "./hooks/docs-active-page-hook.js";
import DocsMobileSidebarHook from "./hooks/docs-mobile-sidebar-hook.js";

import "./docs.css";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let cspNonce = document.querySelector("meta[name='csp-nonce']").getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken, _csp_nonce: cspNonce },
  hooks: {
    ...Noora.Hooks,
    DocsActivePage: DocsActivePageHook,
    DocsContent: DocsContentHook,
    DocsInstallTabs: DocsInstallTabsHook,
    DocsMobileSidebar: DocsMobileSidebarHook,
  },
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
