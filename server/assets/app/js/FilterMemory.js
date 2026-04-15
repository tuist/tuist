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
  window.addEventListener("phx:page-loading-stop", rememberCurrent);
  rememberCurrent();
}
