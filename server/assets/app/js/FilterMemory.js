const STORAGE_PREFIX = "tuist:filter-memory:";
const MARKER_ATTR = "data-filter-memory";

function storageKey(pathname) {
  return STORAGE_PREFIX + pathname;
}

function rememberCurrent() {
  if (!document.querySelector(`[${MARKER_ATTR}]`)) return;
  sessionStorage.setItem(
    storageKey(window.location.pathname),
    window.location.search.slice(1),
  );
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

export function installFilterMemory() {
  document.addEventListener("click", onLinkClick, true);
  // Covers server push_patch, link navigations, and popstate (back/forward).
  window.addEventListener("phx:navigate", rememberCurrent);
  // phx:replace-url silently updates the URL via history.replaceState with no
  // LiveView event of its own. Defer to the next tick so the URL is updated
  // regardless of listener registration order.
  window.addEventListener("phx:replace-url", () => setTimeout(rememberCurrent, 0));
  rememberCurrent();
}
