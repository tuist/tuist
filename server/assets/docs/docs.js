// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
// import { Hooks } from "./js/hooks.js";
import Noora from "noora";
import "./docs.css";

const DocsActivePage = {
  mounted() {
    this._updateSidebar();
  },
  updated() {
    this._updateSidebar();
  },
  _updateSidebar() {
    const currentSlug = this.el.dataset.currentSlug;

    // Update sidebar active item
    const sidebar = document.getElementById("docs-sidebar");
    if (sidebar) {
      sidebar.querySelectorAll("a[data-part='nav-link'], a[data-part='trigger']").forEach((link) => {
        const tabMenu = link.querySelector(".noora-tab-menu-vertical");
        if (!tabMenu) return;
        const href = link.getAttribute("href");
        if (href && href === "/docs" + currentSlug) {
          tabMenu.setAttribute("data-selected", "true");
        } else {
          tabMenu.removeAttribute("data-selected");
        }
      });

      sidebar.querySelectorAll(".noora-tab-menu-vertical[data-part='trigger']").forEach((el) => {
        el.removeAttribute("data-selected");
      });
    }

    // Update nav tab selection
    const navTabs = document.getElementById("docs-nav-tabs");
    if (navTabs) {
      const activeTab = this.el.dataset.currentTab;
      navTabs.querySelectorAll(".noora-button-group-item").forEach((tab) => {
        if (tab.dataset.tab === activeTab) {
          tab.setAttribute("data-selected", "");
        } else {
          tab.removeAttribute("data-selected");
        }
      });
    }
  },
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let cspNonce = document.querySelector("meta[name='csp-nonce']").getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken, _csp_nonce: cspNonce },
  hooks: { ...Noora.Hooks, DocsActivePage },
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
