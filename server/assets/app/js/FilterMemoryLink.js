const BASE_ATTR = "data-filter-memory-base";

export default {
  mounted() {
    const current = this.el.getAttribute("href") || "";
    this.el.setAttribute(BASE_ATTR, current.split("?")[0]);
    this.handler = (event) => this.apply(event.detail && event.detail.queries);
    window.addEventListener("phx:filter-memory", this.handler);
  },

  destroyed() {
    window.removeEventListener("phx:filter-memory", this.handler);
  },

  apply(queries) {
    const key = this.el.dataset.routeKey;
    if (!key || !queries) return;
    const base = this.el.getAttribute(BASE_ATTR);
    const q = queries[key];
    this.el.setAttribute("href", q ? `${base}?${q}` : base);
  },
};
