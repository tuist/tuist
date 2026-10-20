/*
 * Marketing-site theming helpers.
 *
 * The root layout's inline bootstrap (root.html.heex) applies the stored
 * preference before CSS loads and handles OS scheme flips; this module is
 * the runtime side — the theme switcher applies preference changes through
 * applyPreferredTheme, and canvas hooks subscribe via onThemeChange.
 *
 * The "preferred-theme" localStorage key is shared with the dashboard, so
 * the marketing site and the app follow the same choice.
 */

export function getPreferredTheme() {
  try {
    const stored = localStorage.getItem("preferred-theme");
    return stored === null || stored === "null" ? "system" : stored;
  } catch (e) {
    return "system";
  }
}

// Apply a preference ("system" | "light" | "dark"): resolve it, set
// color-scheme + data-theme on <html> (Noora's colors key off color-scheme,
// its shadow tokens off data-theme), persist it, and notify listeners.
export function applyPreferredTheme(preference) {
  const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const resolved = preference === "system" ? (systemDark ? "dark" : "light") : preference;
  document.documentElement.style.setProperty("color-scheme", preference === "system" ? "light dark" : preference);
  document.documentElement.setAttribute("data-theme", resolved);
  try {
    localStorage.setItem("preferred-theme", preference);
  } catch (e) {
    // localStorage may be unavailable (private mode); the theme still applies.
  }
  window.dispatchEvent(new CustomEvent("tuist:theme-change", { detail: { theme: resolved, preference } }));
}

/*
 * Theme-change subscription for canvas hooks.
 *
 * The canvas hooks resolve CSS token colors into raw RGB once at mount, so
 * a runtime scheme flip (the theme switcher, or the OS switching while the
 * page is open) would leave them painted with stale colors. Hooks subscribe
 * here and re-resolve + repaint.
 *
 * Returns an unsubscribe function for the hook's destroyed() callback.
 */
export function onThemeChange(callback) {
  const handler = () => callback();
  window.addEventListener("tuist:theme-change", handler);
  return () => window.removeEventListener("tuist:theme-change", handler);
}
