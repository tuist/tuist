import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../app/js/vendor/topbar.js";
import Noora from "noora";
import ThemeSwitcher, { observeThemeChanges } from "../app/js/ThemeSwitcher.js";
import DocsContentHook from "./hooks/docs-content-hook.js";
import DocsInstallTabsHook from "./hooks/docs-install-tabs-hook.js";
import MermaidDiagramHook from "./hooks/mermaid-diagram-hook.js";
import { initDocsSearch } from "./hooks/docs-search-hook.js";

import "./docs.css";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let cspNonce = document.querySelector("meta[name='csp-nonce']").getAttribute("content");

observeThemeChanges();

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken, _csp_nonce: cspNonce },
  hooks: {
    ...Noora.Hooks,
    DocsContent: DocsContentHook,
    DocsInstallTabs: DocsInstallTabsHook,
    MermaidDiagram: MermaidDiagramHook,
    ThemeSwitcher,
  },
});

topbar.config({
  barColors: { 0: "#29d" },
  shadowColor: "rgba(0, 0, 0, .3)",
});
function closeMobileSidebar() {
  document.body.removeAttribute("data-sidebar-open");
  document.getElementById("docs-sidebar")?.removeAttribute("data-mobile-open");
}

function maybeScrollToTopForNavigation({ kind, to } = {}) {
  if (!to || kind === "initial") return;

  const destination = new URL(to, window.location.origin);
  if (destination.hash) return;

  requestAnimationFrame(() => {
    window.scrollTo(0, 0);
  });
}

window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (info) => {
  topbar.hide();
  maybeScrollToTopForNavigation(info.detail);
  closeMobileSidebar();
  initDocsSearch();
});

liveSocket.connect();

window.addEventListener("phx:navigate", () => {
  if (globalThis.analytics.enabled) {
    posthog.capture("$pageview");
  }
});

window.liveSocket = liveSocket;

initDocsSearch();

window.addEventListener("phx:docs:copy-to-clipboard", ({ detail }) => {
  navigator.clipboard.writeText(detail.text);
});

// TOC scroll spy
function setupTocScrollSpy() {
  const toc = document.getElementById("docs-toc");
  if (!toc) return;

  const tocLinks = toc.querySelectorAll('[data-part="list"] a');
  if (!tocLinks.length) return;

  const headingIds = Array.from(tocLinks).map((a) => a.getAttribute("href")?.replace("#", ""));
  const headings = headingIds.map((id) => document.getElementById(id)).filter(Boolean);

  if (!headings.length) return;

  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          tocLinks.forEach((link) => link.removeAttribute("data-active"));
          const active = toc.querySelector(`[data-part="list"] a[href="#${entry.target.id}"]`);
          active?.setAttribute("data-active", "");
          break;
        }
      }
    },
    { rootMargin: "0px 0px -80% 0px", threshold: 0 },
  );

  headings.forEach((h) => observer.observe(h));
  return observer;
}

let tocObserver = null;
window.addEventListener("phx:page-loading-stop", () => {
  tocObserver?.disconnect();
  requestAnimationFrame(() => {
    tocObserver = setupTocScrollSpy();
  });
});

window.addEventListener("phx:js-exec", ({ detail }) => {
  document.querySelectorAll(detail.to).forEach((el) => {
    liveSocket.execJS(el, el.getAttribute(detail.attr));
  });
});
