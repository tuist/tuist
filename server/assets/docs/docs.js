// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import Noora from "noora";
import { highlightCodeBlocks } from "../shared/js/hooks/shiki-highlight.js";
import { setupCodeCopy } from "../shared/js/hooks/code-copy.js";
import { setupCodeGroups } from "../shared/js/hooks/code-group.js";
import "./docs.css";

const DocsContent = {
  async mounted() {
    await highlightCodeBlocks(this.el);
    setupCodeCopy(this.el);
    setupCodeGroups(this.el);
  },
  async updated() {
    await highlightCodeBlocks(this.el);
    setupCodeCopy(this.el);
    setupCodeGroups(this.el);
  },
};

const DocsInstallTabs = {
  mounted() {
    const tabs = this.el.querySelectorAll("[data-part='terminal-tab']");
    const body = this.el.querySelector("[data-part='terminal-body'] code");
    const commands = { mise: "mise install tuist", homebrew: "brew install tuist/tuist/tuist" };

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        tabs.forEach((t) => t.removeAttribute("data-selected"));
        tab.setAttribute("data-selected", "");
        if (body) body.textContent = commands[tab.textContent.trim()] || "";
      });
    });

    const copyBtn = this.el.querySelector("[data-part='terminal-copy']");
    if (copyBtn && body) {
      copyBtn.addEventListener("click", () => {
        navigator.clipboard.writeText(body.textContent.trim());
      });
    }
  },
};

const DocsActivePage = {
  mounted() {
    this._updateSidebar();
  },
  updated() {
    this._updateSidebar();
    window.scrollTo(0, 0);
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

const DocsMobileSidebar = {
  mounted() {
    const sidebar = document.getElementById("docs-sidebar");
    const overlay = document.getElementById("docs-mobile-sidebar-overlay");
    const body = document.body;

    const open = () => {
      body.setAttribute("data-sidebar-open", "");
      sidebar?.setAttribute("data-mobile-open", "");
    };

    const close = () => {
      body.removeAttribute("data-sidebar-open");
      sidebar?.removeAttribute("data-mobile-open");
    };

    this.el.addEventListener("click", () => {
      const isOpen = body.hasAttribute("data-sidebar-open");
      isOpen ? close() : open();
    });

    const navToggle = document.querySelector("[data-action='toggle-sidebar']");
    navToggle?.addEventListener("click", () => {
      const isOpen = body.hasAttribute("data-sidebar-open");
      isOpen ? close() : open();
    });

    overlay?.addEventListener("click", close);

    sidebar?.addEventListener("click", (e) => {
      if (e.target.closest("a[data-part='nav-link'], a[data-part='trigger']")) {
        close();
      }
    });
  },
};

const DocsMobileToc = {
  mounted() {
    this.el.addEventListener("click", () => {
      const toc = document.getElementById("docs-mobile-toc");
      if (!toc) return;
      const isOpen = toc.getAttribute("data-state") === "open";
      toc.setAttribute("data-state", isOpen ? "closed" : "open");
    });

    const toc = document.getElementById("docs-mobile-toc");
    if (toc) {
      toc.addEventListener("click", (e) => {
        if (e.target.closest("[data-part='mobile-toc-item'], .noora-link-button")) {
          toc.setAttribute("data-state", "closed");
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
  hooks: { ...Noora.Hooks, DocsActivePage, DocsContent, DocsInstallTabs, DocsMobileSidebar, DocsMobileToc },
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
