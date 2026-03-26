import Typesense from "typesense";

const COLLECTIONS = [
  {
    name: "tuist",
    label: "Documentation",
    icon: "hash",
    external: false,
    queryBy:
      "hierarchy.lvl0,hierarchy.lvl1,hierarchy.lvl2,hierarchy.lvl3,hierarchy.lvl4,hierarchy.lvl5,hierarchy.lvl6,content",
    queryByWeights: "127,100,80,60,40,20,10,5",
    groupBy: "url_without_anchor",
  },
  {
    name: "projectdescription",
    label: "ProjectDescription",
    icon: "swift",
    external: true,
    queryBy: "title,hierarchy.lvl0,hierarchy.lvl1,hierarchy.lvl2,content",
    queryByWeights: "127,100,80,60,5",
    groupBy: null,
  },
  {
    name: "github-issues",
    label: "GitHub Issues",
    icon: "github",
    external: true,
    queryBy: "title,hierarchy.lvl0,hierarchy.lvl1,content",
    queryByWeights: "127,100,80,5",
    groupBy: null,
  },
  {
    name: "forum-topics",
    label: "Community",
    icon: "community",
    external: true,
    queryBy:
      "hierarchy.lvl0,hierarchy.lvl1,hierarchy.lvl2,hierarchy.lvl3,hierarchy.lvl4,hierarchy.lvl5,hierarchy.lvl6,content",
    queryByWeights: "127,100,80,60,40,20,10,5",
    groupBy: "url_without_anchor",
  },
];

// --- Hit helpers ---

function titleFor(hit) {
  const doc = hit.document;
  if (doc.title) return doc.title;
  const h = doc.hierarchy || {};
  if (h.lvl0) return h.lvl0;
  for (let i = 1; i <= 6; i++) {
    if (h[`lvl${i}`]) return h[`lvl${i}`];
  }
  const content = doc.content || "";
  return content.length > 80 ? content.slice(0, 80) + "..." : content || doc.url || "";
}

function subtitleFor(hit) {
  const doc = hit.document;
  if (doc.role) return doc.role;
  const h = doc.hierarchy || {};
  const page = h.lvl0 || "";
  for (let i = 6; i >= 1; i--) {
    if (h[`lvl${i}`] && h[`lvl${i}`] !== page) return h[`lvl${i}`];
  }
  return "";
}

function urlFor(hit) {
  return hit.document.url_without_anchor || hit.document.url || "#";
}

function highlightMatch(text, query) {
  if (!text || !query) return escapeHtml(text || "");
  const escaped = escapeHtml(text);
  const re = new RegExp(`(${query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi");
  return escaped.replace(re, '<mark data-part="highlight">$1</mark>');
}

function escapeHtml(str) {
  const el = document.createElement("span");
  el.textContent = str;
  return el.innerHTML;
}

// --- Hook ---

export default {
  mounted() {
    this.results = [];
    this.selectedIndex = -1;
    this.debounceTimer = null;

    this.client = this._createClient();
    this.modal = this.el.querySelector('[data-part="modal"]');
    this.backdrop = this.el.querySelector('[data-part="backdrop"]');
    this.input = this.el.querySelector('[data-part="search-input"]');
    this.resultsEl = this.el.querySelector('[data-part="results"]');
    this.emptyState = this.el.querySelector('[data-part="empty-state"]');
    this.groupTpl = this.el.querySelector('[data-template="group"]');
    this.resultTpl = this.el.querySelector('[data-template="result"]');

    this._bindGlobalShortcut();
    this._bindSearchBarTriggers();
    this._bindModalEvents();
  },

  destroyed() {
    window.removeEventListener("keydown", this._onGlobalKeydown);
    clearTimeout(this.debounceTimer);
  },

  // --- Public (callable from outside) ---

  open() {
    this.modal.setAttribute("data-state", "open");
    this.backdrop.setAttribute("data-state", "open");
    document.body.style.overflow = "hidden";
    requestAnimationFrame(() => this.input?.focus());
  },

  // --- Client setup ---

  _createClient() {
    const host = this.el.dataset.host || "https://search.tuist.dev";
    const apiKey = this.el.dataset.apiKey || "";
    return new Typesense.Client({
      nodes: [{ host: new URL(host).hostname, port: 443, protocol: "https" }],
      apiKey,
      connectionTimeoutSeconds: 5,
    });
  },

  // --- Event binding ---

  _bindGlobalShortcut() {
    this._onGlobalKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        this.open();
      }
    };
    window.addEventListener("keydown", this._onGlobalKeydown);
  },

  _bindSearchBarTriggers() {
    const openSearch = (e) => {
      e.preventDefault();
      this.open();
    };

    const searchBar = document.querySelector("#text-input-types-search");
    if (searchBar) {
      searchBar.addEventListener("focus", (e) => {
        e.preventDefault();
        e.target.blur();
        this.open();
      });
    }

    const wrapper = document.querySelector('.noora-text-input:has(#text-input-types-search) [data-part="wrapper"]');
    if (wrapper) wrapper.addEventListener("click", openSearch);

    const mobileBtn = document.querySelector('#docs-nav [data-part="mobile-actions"] button:first-child');
    if (mobileBtn) mobileBtn.addEventListener("click", openSearch);
  },

  _bindModalEvents() {
    this.backdrop.addEventListener("click", () => this._close());

    this.input.addEventListener("input", (e) => {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(() => this._search(e.target.value), 200);
    });

    this.input.addEventListener("keydown", (e) => {
      switch (e.key) {
        case "ArrowDown":
          e.preventDefault();
          this._moveSelection(1);
          break;
        case "ArrowUp":
          e.preventDefault();
          this._moveSelection(-1);
          break;
        case "Enter":
          e.preventDefault();
          this._selectCurrent();
          break;
        case "Escape":
          e.preventDefault();
          this._close();
          break;
      }
    });
  },

  // --- Search ---

  async _search(query) {
    if (!query || query.length < 2) {
      this.results = [];
      this.selectedIndex = -1;
      this._renderResults([]);
      return;
    }

    const locale = this.el.dataset.locale || document.documentElement.lang || "en";

    try {
      const response = await this.client.multiSearch.perform({
        searches: COLLECTIONS.map((col) => ({
          collection: col.name,
          q: query,
          query_by: col.queryBy,
          query_by_weights: col.queryByWeights,
          highlight_full_fields: col.queryBy,
          ...(col.groupBy ? { group_by: col.groupBy, group_limit: 1 } : {}),
          per_page: 5,
          ...(col.name === "tuist" ? { filter_by: `tags:=${locale}` } : {}),
        })),
      });

      const grouped = [];
      this.results = [];

      response.results.forEach((result, idx) => {
        const col = COLLECTIONS[idx];
        const hits = col.groupBy
          ? (result.grouped_hits || []).map((g) => g.hits[0]).filter(Boolean)
          : result.hits || [];

        if (hits.length > 0) {
          grouped.push({ ...col, hits });
          for (const hit of hits) {
            this.results.push({ hit, collection: col });
          }
        }
      });

      this.selectedIndex = this.results.length > 0 ? 0 : -1;
      this._renderResults(grouped, query);
    } catch (err) {
      console.error("Search error:", err);
    }
  },

  // --- Rendering (template cloning) ---

  _renderResults(grouped, query = "") {
    if (grouped.length === 0) {
      this.resultsEl.innerHTML = "";
      this.emptyState.textContent = this.input.value.length >= 2 ? "No results found" : "No search history";
      this.emptyState.style.display = "";
      return;
    }

    this.emptyState.style.display = "none";
    this.resultsEl.innerHTML = "";
    let flatIndex = 0;

    for (const group of grouped) {
      const groupEl = this.groupTpl.content.cloneNode(true);
      const label = groupEl.querySelector('[data-part="group-label"]');

      // Insert icon from server-rendered template
      const iconTpl = this.el.querySelector(`[data-icon="${group.icon}"]`);
      if (iconTpl) label.appendChild(iconTpl.content.cloneNode(true));

      const span = document.createElement("span");
      span.textContent = group.label;
      label.appendChild(span);

      const groupContainer = groupEl.querySelector('[data-part="result-group"]');

      for (const hit of group.hits) {
        const resultEl = this.resultTpl.content.cloneNode(true);
        const link = resultEl.querySelector('[data-part="result-item"]');
        const titleEl = resultEl.querySelector('[data-part="result-title"]');
        const subtitleEl = resultEl.querySelector('[data-part="result-subtitle"]');

        const title = titleFor(hit);
        const subtitle = subtitleFor(hit);

        link.href = urlFor(hit);
        link.dataset.index = flatIndex;
        if (flatIndex === this.selectedIndex) link.setAttribute("data-selected", "");
        if (group.external) {
          link.target = "_blank";
          link.rel = "noopener noreferrer";
        }

        titleEl.innerHTML = highlightMatch(title, query);

        if (subtitle && subtitle !== title) {
          subtitleEl.textContent = subtitle;
        } else {
          subtitleEl.remove();
        }

        link.addEventListener("mouseenter", () => {
          this.selectedIndex = parseInt(link.dataset.index, 10);
          this._updateSelection();
        });

        groupContainer.appendChild(resultEl);
        flatIndex++;
      }

      this.resultsEl.appendChild(groupEl);
    }
  },

  // --- Navigation ---

  _close() {
    this.modal.removeAttribute("data-state");
    this.backdrop.removeAttribute("data-state");
    document.body.style.overflow = "";
    this.input.value = "";
    this.results = [];
    this.selectedIndex = -1;
    this._renderResults([]);
  },

  _moveSelection(direction) {
    if (this.results.length === 0) return;
    this.selectedIndex = (this.selectedIndex + direction + this.results.length) % this.results.length;
    this._updateSelection();
  },

  _updateSelection() {
    for (const [idx, item] of this.resultsEl.querySelectorAll('[data-part="result-item"]').entries()) {
      if (idx === this.selectedIndex) {
        item.setAttribute("data-selected", "");
        item.scrollIntoView({ block: "nearest" });
      } else {
        item.removeAttribute("data-selected");
      }
    }
  },

  _selectCurrent() {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.results.length) return;
    const { hit, collection } = this.results[this.selectedIndex];
    const url = urlFor(hit);
    this._close();
    if (collection.external) {
      window.open(url, "_blank", "noopener,noreferrer");
    } else {
      window.location.href = url;
    }
  },
};
