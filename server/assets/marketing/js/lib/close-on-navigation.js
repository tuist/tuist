/**
 * Closes a navbar menu the instant one of its links is followed, and as a
 * safety net right before the document is swapped out.
 *
 * Page switches are cross-document view transitions, and the outgoing page
 * is captured at `pageswap`, which fires when the next page's response has
 * arrived — with a prefetched page that is milliseconds after the click, so
 * an open panel (or one still fading) was captured, carried across in the
 * navbar's snapshot, and then vanished when the transition ended. Closing
 * synchronously on the click, with transitions suppressed, means the menu is
 * gone before the browser even starts navigating; the `pageswap` listener
 * covers navigations that don't start from a click inside the menu
 * (keyboard, the address bar). Only same-tab navigations count: modified
 * clicks and `target="_blank"` links leave the menu as it is.
 */
export function closeOnNavigation(root, close) {
  const instantly = () => {
    const navbar = document.getElementById("marketing-navbar");
    if (!navbar) return close();
    navbar.dataset.instant = "";
    close();
    // Flush styles while transitions are off, so restoring them afterwards
    // doesn't start one from the already-applied closed state.
    void navbar.offsetWidth;
    delete navbar.dataset.instant;
  };

  const onClick = (event) => {
    const link = event.target.closest?.("a[href]");
    if (!link || !root.contains(link)) return;
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (link.target && link.target !== "_self") return;
    if (link.hasAttribute("download")) return;
    instantly();
  };

  root.addEventListener("click", onClick);
  window.addEventListener("pageswap", instantly);
  return () => {
    root.removeEventListener("click", onClick);
    window.removeEventListener("pageswap", instantly);
  };
}
