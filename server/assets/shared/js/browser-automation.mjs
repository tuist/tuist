const LINUX_CRAWLER_USER_AGENT =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36";

export function isAutomatedBrowser(navigator, viewport) {
  if (navigator.webdriver || /^meta-externalagent\//i.test(navigator.userAgent)) {
    return true;
  }

  // This client kept emitting queued login-page navigations after the WebDriver
  // guard shipped. Match its full observed fingerprint to limit false positives.
  return (
    navigator.userAgent === LINUX_CRAWLER_USER_AGENT &&
    navigator.language === "en-US" &&
    viewport.innerWidth === 1919 &&
    viewport.innerHeight === 992
  );
}
