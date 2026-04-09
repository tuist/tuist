import Typesense from "typesense";

// --- Configuration ---

const DEFAULT_PER_PAGE = 5;

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
    perPage: 1,
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

// --- Text utilities ---

const MARKDOWN_STRIP_RULES = [
  [/^#{1,6}\s+/gm, ""],
  [/\*\*(.+?)\*\*/g, "$1"],
  [/__(.+?)__/g, "$1"],
  [/\*(.+?)\*/g, "$1"],
  [/_(.+?)_/g, "$1"],
  [/~~(.+?)~~/g, "$1"],
  [/`(.+?)`/g, "$1"],
  [/!\[([^\]]*)\]\([^)]+\)/g, "$1"],
  [/\[([^\]]+)\]\([^)]+\)/g, "$1"],
  [/https?:\/\/\S+/g, ""],
  [/[*_~`]+/g, ""],
  [/\s·\s*(issues|pull|pull requests?)\b/gi, ""],
  [/\s+/g, " "],
];

function stripMarkdown(text) {
  return MARKDOWN_STRIP_RULES.reduce((s, [re, rep]) => s.replace(re, rep), text).trim();
}

function truncate(text, max = 80) {
  return text.length > max ? text.slice(0, max) + "..." : text;
}

function escapeHtml(str) {
  const el = document.createElement("span");
  el.textContent = str;
  return el.innerHTML;
}

function highlightQuery(text, query) {
  if (!text || !query) return escapeHtml(text || "");
  const escaped = escapeHtml(text);
  const pattern = query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return escaped.replace(new RegExp(`(${pattern})`, "gi"), '<mark data-part="highlight">$1</mark>');
}

// --- Hit data extraction ---

function titleFor(hit) {
  const { document: doc } = hit;
  if (doc.title) return doc.title;
  const h = doc.hierarchy || {};
  for (let i = 0; i <= 6; i++) {
    if (h[`lvl${i}`]) return h[`lvl${i}`];
  }
  return truncate(doc.content || doc.url || "");
}

function urlFor(hit) {
  return hit.document.url_without_anchor || hit.document.url || "#";
}

function contentHighlightFor(hit) {
  const hl = hit.highlights || hit.highlight || [];
  return Array.isArray(hl) ? hl.find((h) => h.field === "content") : hl.content;
}

function contentSnippetFor(hit) {
  const fullContent = (hit.document.content || "").trim();
  const highlight = contentHighlightFor(hit);

  if (highlight) {
    const raw = highlight.snippet || highlight.value || "";
    if (raw) {
      const clean = stripMarkdown(raw.replace(/<\/?mark>/g, ""));
      const fullClean = stripMarkdown(fullContent);
      const prefix = fullClean.startsWith(clean) ? "" : "...";
      const suffix = fullClean.endsWith(clean) ? "" : "...";
      return `${prefix}${clean}${suffix}`;
    }
  }

  return fullContent ? truncate(stripMarkdown(fullContent)) : "";
}

function subtitleFor(hit) {
  const { document: doc } = hit;
  const snippet = contentSnippetFor(hit);

  if (contentHighlightFor(hit) && snippet) return snippet;
  if (doc.role) return doc.role;

  const h = doc.hierarchy || {};
  const title = titleFor(hit);
  const page = h.lvl0 || "";
  for (let i = 6; i >= 1; i--) {
    if (h[`lvl${i}`] && h[`lvl${i}`] !== page && h[`lvl${i}`] !== title) return h[`lvl${i}`];
  }

  return snippet;
}

function displayUrl(url, external) {
  if (external) return decodeURIComponent(url);
  try {
    return decodeURIComponent(new URL(url, window.location.origin).pathname);
  } catch {
    return url;
  }
}

// --- Singleton lifecycle ---

let _instance = null;

export function initDocsSearch() {
  const el = document.getElementById("docs-search");
  if (!el) return;
  if (_instance) _instance.destroy();
  _instance = new DocsSearch(el);
}

// --- Search controller ---

class DocsSearch {
  constructor(el) {
    this.el = el;
    this._results = [];
    this._selectedIndex = -1;
    this._debounceTimer = null;
    this._listeners = [];

    this._client = this._createClient();
    this._modal = el.querySelector('[data-part="modal"]');
    this._backdrop = el.querySelector('[data-part="backdrop"]');
    this._input = el.querySelector('[data-part="search-input"]');
    this._resultsEl = el.querySelector('[data-part="results"]');
    this._emptyState = el.querySelector('[data-part="empty-state"]');
    this._groupTpl = el.querySelector('[data-template="group"]');
    this._resultTpl = el.querySelector('[data-template="result"]');

    this._bindGlobalShortcut();
    this._bindSearchBarTriggers();
    this._bindModalEvents();
  }

  destroy() {
    window.removeEventListener("keydown", this._onGlobalKeydown);
    clearTimeout(this._debounceTimer);
    for (const { el, event, handler } of this._listeners) {
      el.removeEventListener(event, handler);
    }
    this._listeners = [];
  }

  open() {
    this._modal.setAttribute("data-state", "open");
    this._backdrop.setAttribute("data-state", "open");
    document.body.setAttribute("data-search-open", "");
    requestAnimationFrame(() => this._input?.focus());
  }

  // --- Private: Typesense client ---

  _createClient() {
    const host = this.el.dataset.host || "https://search.tuist.dev";
    return new Typesense.Client({
      nodes: [{ host: new URL(host).hostname, port: 443, protocol: "https" }],
      apiKey: this.el.dataset.apiKey || "",
      connectionTimeoutSeconds: 5,
    });
  }

  // --- Private: event binding ---

  _on(el, event, handler) {
    el.addEventListener(event, handler);
    this._listeners.push({ el, event, handler });
  }

  _bindGlobalShortcut() {
    this._onGlobalKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        this.open();
      }
    };
    window.addEventListener("keydown", this._onGlobalKeydown);
  }

  _bindSearchBarTriggers() {
    const trigger = (e) => {
      e.preventDefault();
      this.open();
    };

    const searchBar = document.querySelector("#text-input-types-search");
    if (searchBar) {
      this._on(searchBar, "focus", (e) => {
        e.preventDefault();
        e.target.blur();
        this.open();
      });
    }

    const wrapper = document.querySelector('.noora-text-input:has(#text-input-types-search) [data-part="wrapper"]');
    if (wrapper) this._on(wrapper, "click", trigger);

    const mobileBtn = document.querySelector('#docs-nav [data-part="mobile-actions"] button:first-child');
    if (mobileBtn) this._on(mobileBtn, "click", trigger);
  }

  _bindModalEvents() {
    this._on(this._backdrop, "click", () => this._close());

    this._on(this._input, "input", (e) => {
      clearTimeout(this._debounceTimer);
      this._debounceTimer = setTimeout(() => this._search(e.target.value), 200);
    });

    this._on(this._input, "keydown", (e) => {
      const actions = {
        ArrowDown: () => this._moveSelection(1),
        ArrowUp: () => this._moveSelection(-1),
        Enter: () => this._selectCurrent(),
        Escape: () => this._close(),
      };
      if (actions[e.key]) {
        e.preventDefault();
        actions[e.key]();
      }
    });
  }

  // --- Private: search ---

  async _search(query) {
    if (!query || query.length < 2) {
      this._reset();
      return;
    }

    const locale = this.el.dataset.locale || document.documentElement.lang || "en";

    try {
      const response = await this._client.multiSearch.perform({
        searches: COLLECTIONS.map((col) => ({
          collection: col.name,
          q: query,
          query_by: col.queryBy,
          query_by_weights: col.queryByWeights,
          highlight_full_fields: col.queryBy,
          per_page: col.perPage || DEFAULT_PER_PAGE,
          ...(col.groupBy ? { group_by: col.groupBy, group_limit: 1 } : {}),
          ...(col.name === "tuist" ? { filter_by: `tags:=${locale}` } : {}),
        })),
      });

      const grouped = [];
      this._results = [];

      response.results.forEach((result, idx) => {
        const col = COLLECTIONS[idx];
        const hits = col.groupBy
          ? (result.grouped_hits || []).map((g) => g.hits[0]).filter(Boolean)
          : result.hits || [];

        if (hits.length > 0) {
          grouped.push({ ...col, hits });
          for (const hit of hits) this._results.push({ hit, collection: col });
        }
      });

      this._selectedIndex = this._results.length > 0 ? 0 : -1;
      this._renderResults(grouped, query);
    } catch (err) {
      console.error("Search error:", err);
    }
  }

  // --- Private: rendering ---

  _renderResults(grouped, query = "") {
    this._resultsEl.replaceChildren();

    if (grouped.length === 0) {
      this._emptyState.textContent = this._input.value.length >= 2 ? "No results found" : "No search history";
      this._emptyState.removeAttribute("data-state");
      return;
    }

    this._emptyState.setAttribute("data-state", "hidden");

    let flatIndex = 0;
    for (const group of grouped) {
      const groupEl = this._groupTpl.content.cloneNode(true);
      const label = groupEl.querySelector('[data-part="group-label"]');

      const iconTpl = this.el.querySelector(`[data-icon="${group.icon}"]`);
      if (iconTpl) label.appendChild(iconTpl.content.cloneNode(true));

      const span = document.createElement("span");
      span.textContent = group.label;
      label.appendChild(span);

      const container = groupEl.querySelector('[data-part="result-group"]');
      for (const hit of group.hits) {
        container.appendChild(this._buildResultEl(hit, group, query, flatIndex++));
      }

      this._resultsEl.appendChild(groupEl);
    }
  }

  _buildResultEl(hit, group, query, index) {
    const frag = this._resultTpl.content.cloneNode(true);
    const link = frag.querySelector('[data-part="result-item"]');
    const titleEl = frag.querySelector('[data-part="result-title"]');
    const subtitleEl = frag.querySelector('[data-part="result-subtitle"]');
    const urlEl = frag.querySelector('[data-part="result-url"]');

    const title = titleFor(hit);
    const subtitle = subtitleFor(hit);
    const url = urlFor(hit);

    link.href = url;
    link.dataset.index = index;
    if (index === this._selectedIndex) link.setAttribute("data-selected", "");
    if (group.external) {
      link.target = "_blank";
      link.rel = "noopener noreferrer";
    }

    titleEl.innerHTML = highlightQuery(title, query);

    if (subtitle && subtitle !== title) {
      subtitleEl.innerHTML = highlightQuery(subtitle, query);
    } else {
      subtitleEl.remove();
    }

    urlEl.textContent = displayUrl(url, group.external);

    link.addEventListener("mouseenter", () => {
      this._selectedIndex = parseInt(link.dataset.index, 10);
      this._updateSelection();
    });

    return frag;
  }

  // --- Private: navigation ---

  _close() {
    this._modal.removeAttribute("data-state");
    this._backdrop.removeAttribute("data-state");
    document.body.removeAttribute("data-search-open");
    this._input.value = "";
    this._reset();
  }

  _reset() {
    this._results = [];
    this._selectedIndex = -1;
    this._renderResults([]);
  }

  _moveSelection(dir) {
    if (this._results.length === 0) return;
    this._selectedIndex = (this._selectedIndex + dir + this._results.length) % this._results.length;
    this._updateSelection();
  }

  _updateSelection() {
    const items = this._resultsEl.querySelectorAll('[data-part="result-item"]');
    for (const [idx, item] of items.entries()) {
      if (idx === this._selectedIndex) {
        item.setAttribute("data-selected", "");
        item.scrollIntoView({ block: "nearest" });
      } else {
        item.removeAttribute("data-selected");
      }
    }
  }

  _selectCurrent() {
    if (this._selectedIndex < 0 || this._selectedIndex >= this._results.length) return;
    const { hit, collection } = this._results[this._selectedIndex];
    const url = urlFor(hit);
    this._close();
    if (collection.external) {
      window.open(url, "_blank", "noopener,noreferrer");
    } else {
      window.location.href = url;
    }
  }
}

export default DocsSearch;
