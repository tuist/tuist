// A new main view joins before push_navigate updates the address bar. LiveView's
// "initial" loading event supplies that destination before connect params run.
export function trackBrowserSessionPath(browser) {
  let path = browser.location.pathname + browser.location.search;
  const remember = (href) => {
    const url = new URL(href, browser.location.href);
    path = url.origin === browser.location.origin ? url.pathname + url.search : null;
  };

  browser.addEventListener("phx:page-loading-start", ({ detail }) => {
    if (detail.kind === "initial" && typeof detail.to === "string") remember(detail.to);
  });
  browser.addEventListener("phx:navigate", ({ detail }) => remember(detail.href));

  return () => path;
}
