import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../app/js/vendor/topbar.js";
import Noora from "noora";
import DocsContentHook from "./hooks/docs-content-hook.js";
import DocsInstallTabsHook from "./hooks/docs-install-tabs-hook.js";
import DocsNavTabsHook from "./hooks/docs-nav-tabs-hook.js";

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
    DocsNavTabs: DocsNavTabsHook,
  },
});

topbar.config({
  barColors: { 0: "#29d" },
  shadowColor: "rgba(0, 0, 0, .3)",
});

const SIDEBAR_SCROLL_SELECTOR = "#docs-sidebar [data-part='sidebar-scroll']";

let savedSidebarScroll = 0;

window.addEventListener("phx:page-loading-start", () => {
  topbar.show(300);
  const el = document.querySelector(SIDEBAR_SCROLL_SELECTOR);
  if (el) savedSidebarScroll = el.scrollTop;
});

window.addEventListener("phx:page-loading-stop", () => {
  topbar.hide();
  window.scrollTo(0, 0);

  document.body.removeAttribute("data-sidebar-open");
  document.getElementById("docs-sidebar")?.removeAttribute("data-mobile-open");

  const el = document.querySelector(SIDEBAR_SCROLL_SELECTOR);
  if (el) el.scrollTop = savedSidebarScroll;
});

liveSocket.connect();

window.addEventListener("phx:navigate", () => {
  if (globalThis.analytics.enabled) {
    posthog.capture("$pageview");
  }
});

window.liveSocket = liveSocket;

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
