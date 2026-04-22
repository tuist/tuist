import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../app/js/vendor/topbar.js";
import Noora from "noora";
import ThemeSwitcher, { ThemeToggle, observeThemeChanges } from "../app/js/ThemeSwitcher.js";
import DocsContentHook from "./hooks/docs-content-hook.js";
import DocsInstallTabsHook from "./hooks/docs-install-tabs-hook.js";
import MermaidDiagramHook from "./hooks/mermaid-diagram-hook.js";
import { initDocsSearch } from "./hooks/docs-search-hook.js";
import { copyTextToClipboard } from "../shared/js/clipboard.js";

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
    ThemeToggle,
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

const copyPageLabelTimeouts = new Map();
const COPY_PAGE_FEEDBACK_DURATION_MS = 3000;

function restoreCopyPageButton(mainButton) {
  const label = mainButton?.querySelector('[data-part="label"]');
  if (!mainButton || !label) return;

  label.textContent = mainButton.dataset.defaultLabel || "Copy page";
  copyPageLabelTimeouts.delete(mainButton);
}

function resetCopyPageButtons() {
  for (const [mainButton, timeoutId] of copyPageLabelTimeouts) {
    clearTimeout(timeoutId);
    restoreCopyPageButton(mainButton);
  }
}

function getDocsPageMarkdown() {
  const markdown = document.getElementById("docs-page-markdown");
  return markdown?.value || "";
}

function flashCopyPageButton(dropdownId) {
  const dropdown = document.getElementById(dropdownId);
  const mainButton = dropdown?.querySelector('[data-part="main-button"]');
  const label = mainButton?.querySelector('[data-part="label"]');
  if (!mainButton || !label) return;

  const defaultLabel = mainButton.dataset.defaultLabel || label.textContent.trim();
  const copiedLabel = mainButton.dataset.copiedLabel || "Copied";
  const existingTimeout = copyPageLabelTimeouts.get(mainButton);

  if (existingTimeout) {
    clearTimeout(existingTimeout);
  }

  label.textContent = copiedLabel;

  const timeoutId = window.setTimeout(() => {
    restoreCopyPageButton(mainButton);
  }, COPY_PAGE_FEEDBACK_DURATION_MS);

  copyPageLabelTimeouts.set(mainButton, timeoutId);
}

function setupCopyPageButtons() {
  document
    .querySelectorAll(
      '#docs-copy-dropdown [data-part="main-button"], #docs-mobile-copy-dropdown [data-part="main-button"]',
    )
    .forEach((button) => {
      if (button.dataset.copyPageBound === "true") return;

      button.dataset.copyPageBound = "true";
      button.addEventListener("click", () => {
        const markdown = getDocsPageMarkdown();
        const dropdownId = button.closest(".noora-button-dropdown")?.id;
        if (!markdown || !dropdownId) return;

        copyTextToClipboard(markdown)
          .then(() => flashCopyPageButton(dropdownId))
          .catch((error) => console.error("Failed to copy page:", error));
      });
    });
}

window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (info) => {
  topbar.hide();
  maybeScrollToTopForNavigation(info.detail);
  closeMobileSidebar();
  initDocsSearch();
  setupCopyPageButtons();
});

window.addEventListener("beforeunload", resetCopyPageButtons);

liveSocket.connect();

window.addEventListener("phx:navigate", () => {
  if (globalThis.analytics.enabled) {
    posthog.capture("$pageview");
  }
});

window.liveSocket = liveSocket;

initDocsSearch();
setupCopyPageButtons();

window.addEventListener("phx:docs:copy-to-clipboard", ({ detail }) => {
  copyTextToClipboard(detail.text)
    .then(() => {
      flashCopyPageButton("docs-copy-dropdown");
      flashCopyPageButton("docs-mobile-copy-dropdown");
    })
    .catch((error) => console.error("Failed to copy page:", error));
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
