/**
 * Per-tab query-string memory for dashboard pages.
 *
 * Remembers the query string (filters, sort, pagination, selected tab, etc.)
 * seen on each pathname and restores it when the user navigates back to that
 * pathname via a plain link — sidebar items, breadcrumbs, detail-page back
 * buttons — without any per-link wiring.
 *
 * Remember side: whenever the URL changes under a `[data-remember-url-query]`
 * marker, write `sessionStorage["tuist:query-memory:" + pathname] = search`.
 * We listen to both `phx:navigate` (link clicks, server `push_patch`,
 * popstate) and `phx:replace-url` (the app-custom silent URL update) because
 * `phx:page-loading-stop` does not fire for server-initiated patches.
 *
 * Restore side: a capture-phase `click` listener on `document` runs before
 * LiveView's own bubble-phase click handler. If the clicked `<a>` has a bare
 * `/...` href with no query of its own, and we have a remembered query for
 * that pathname, we rewrite the `href` in place. LiveView then reads the
 * rewritten href and navigates with the restored query.
 *
 * State lives in `sessionStorage`, which is scoped to the browsing context
 * and cleared when the tab closes.
 */

const STORAGE_PREFIX = "tuist:query-memory:";
const MARKER_ATTR = "data-remember-url-query";

function storageKey(pathname) {
  return STORAGE_PREFIX + pathname;
}

function rememberCurrent() {
  if (!document.querySelector(`[${MARKER_ATTR}]`)) return;
  sessionStorage.setItem(storageKey(window.location.pathname), window.location.search.slice(1));
}

function onLinkClick(event) {
  if (event.defaultPrevented) return;
  const anchor = event.target.closest('a[href^="/"]');
  if (!anchor) return;
  const href = anchor.getAttribute("href");
  if (href.includes("?")) return;
  const remembered = sessionStorage.getItem(storageKey(href));
  if (remembered) anchor.setAttribute("href", `${href}?${remembered}`);
}

/**
 * Attach the global listeners. Call once on app startup, after the DOM is
 * ready and after LiveSocket is set up so that our capture-phase click
 * listener runs before LiveView's bubble-phase one.
 */
export function setupQueryMemory() {
  document.addEventListener("click", onLinkClick, true);
  window.addEventListener("phx:navigate", rememberCurrent);
  // Deferred to the next tick so the URL has been updated by the existing
  // `phx:replace-url` listener before we read `window.location`.
  window.addEventListener("phx:replace-url", () => setTimeout(rememberCurrent, 0));
  rememberCurrent();
}
