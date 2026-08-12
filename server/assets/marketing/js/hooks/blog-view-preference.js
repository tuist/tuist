/**
 * Remembers the blog index's grid/list choice.
 *
 * The switcher puts the active view in the URL, which covers navigation within
 * a visit; this persists it across visits so someone who prefers the list
 * doesn't land on the grid every time. A cookie rather than localStorage
 * because the server reads it (mirrored into the session by
 * TuistWeb.Marketing.Preferences) and renders the right view on first paint —
 * localStorage would only be readable after the page had already drawn.
 */
const COOKIE = "tuist_blog_view";
const MAX_AGE = 60 * 60 * 24 * 365;
const VIEWS = ["grid", "list"];

function persist(el) {
  const view = el.dataset.viewMode;
  if (!VIEWS.includes(view)) return;

  document.cookie = `${COOKIE}=${view}; path=/; max-age=${MAX_AGE}; samesite=lax`;
}

export const BlogViewPreference = {
  mounted() {
    persist(this.el);
  },
  updated() {
    persist(this.el);
  },
};
