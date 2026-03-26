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

// --- Icons ---

const ICONS = {
  search: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>`,
  hash: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="4" y1="9" x2="20" y2="9"/><line x1="4" y1="15" x2="20" y2="15"/><line x1="10" y1="3" x2="8" y2="21"/><line x1="16" y1="3" x2="14" y2="21"/></svg>`,
  swift: `<svg width="16" height="16" viewBox="1 3 29 25" xmlns="http://www.w3.org/2000/svg"><path d="M19.422,4.007s6.217,3.554,7.844,9.2c1.466,5.1.292,7.534.292,7.534a8.915,8.915,0,0,1,1.742,2.8,4.825,4.825,0,0,1,.29,4.453s-.1-2.08-3.2-2.511c-2.841-.4-3.874,2.366-9.3,2.232A18.435,18.435,0,0,1,2,19.354C4.651,20.8,8.124,23.045,12.449,22.7s5.228-1.674,5.228-1.674A66.9,66.9,0,0,1,4.891,7.643c3.4,2.845,11.822,8.507,11.626,8.363A75.826,75.826,0,0,1,8.092,6.24S20.728,16.629,21.745,16.563c.418-.861,2.579-5.318-2.324-12.557Z" fill="#F05138"/></svg>`,
  github: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M9 19c-4.3 1.4 -4.3 -2.5 -6 -3m12 5v-3.5c0 -1 .1 -1.4 -.5 -2c2.8 -.3 5.5 -1.4 5.5 -6a4.6 4.6 0 0 0 -1.3 -3.2a4.2 4.2 0 0 0 -.1 -3.2s-1.1 -.3 -3.5 1.3a12.3 12.3 0 0 0 -6.2 0c-2.4 -1.6 -3.5 -1.3 -3.5 -1.3a4.2 4.2 0 0 0 -.1 3.2a4.6 4.6 0 0 0 -1.3 3.2c0 4.6 2.7 5.7 5.5 6c-.6 .6 -.6 1.2 -.5 2v3.5"/></svg>`,
  community: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" clip-rule="evenodd" d="M6.97872 6.54172C10.1369 4.30173 14.6947 4.49268 17.596 6.96693L6.97872 6.54172ZM17.596 6.96693C20.4502 9.4021 20.8093 13.2718 18.5023 16.0712C16.1504 18.925 11.7101 19.8354 8.13675 18.1006C7.93653 18.0034 7.7096 17.9758 7.49191 18.0221L4.50139 18.6584L5.2487 16.4164C5.34701 16.1215 5.30256 15.7976 5.12842 15.54C3.12975 12.5842 3.86507 8.75123 6.97872 6.54172M5.82147 4.91053C9.71524 2.14867 15.2853 2.36771 18.8939 5.44531C22.5496 8.56415 23.0707 13.6726 20.0457 17.3432C17.1379 20.8716 11.8714 21.9565 7.58154 20.0478L3.20813 20.9783C2.85732 21.0529 2.49341 20.934 2.25441 20.6666C2.0154 20.3991 1.93792 20.0242 2.05133 19.684L3.20102 16.2349C0.902056 12.3841 2.0244 7.60488 5.82147 4.91053Z" fill="currentColor"/></svg>`,
  enter: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 10 4 15 9 20"/><path d="M20 4v7a4 4 0 0 1-4 4H4"/></svg>`,
  arrowUp: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/></svg>`,
  arrowDown: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><polyline points="19 12 12 19 5 12"/></svg>`,
};

// --- Helpers ---

function escapeHtml(str) {
  const el = document.createElement("span");
  el.textContent = str;
  return el.innerHTML;
}

function highlightMatch(text, query) {
  if (!text || !query) return escapeHtml(text || "");
  const escaped = escapeHtml(text);
  const re = new RegExp(`(${query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi");
  return escaped.replace(re, '<mark data-part="highlight">$1</mark>');
}

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

// --- Web Component ---

class DocsSearchElement extends HTMLElement {
  #client;
  #results = [];
  #selectedIndex = -1;
  #debounceTimer = null;

  // DOM refs
  #modal;
  #backdrop;
  #input;
  #resultsEl;
  #emptyState;

  // Bound handlers for cleanup
  #onGlobalKeydown;

  connectedCallback() {
    this.#initClient();
    this.#render();
    this.#bindEvents();
  }

  disconnectedCallback() {
    window.removeEventListener("keydown", this.#onGlobalKeydown);
    clearTimeout(this.#debounceTimer);
  }

  open() {
    this.#modal.setAttribute("data-state", "open");
    this.#backdrop.setAttribute("data-state", "open");
    document.body.style.overflow = "hidden";
    requestAnimationFrame(() => this.#input?.focus());
  }

  // --- Private ---

  #initClient() {
    const host = this.getAttribute("host") || "https://search.tuist.dev";
    const apiKey = this.getAttribute("api-key") || "";

    this.#client = new Typesense.Client({
      nodes: [{ host: new URL(host).hostname, port: 443, protocol: "https" }],
      apiKey,
      connectionTimeoutSeconds: 5,
    });
  }

  #render() {
    const placeholder = this.getAttribute("search-placeholder") || "Search...";

    this.innerHTML = `
      <div data-part="backdrop"></div>
      <div data-part="modal">
        <div data-part="search-wrapper">
          <div data-part="input-container">
            <span data-part="search-icon">${ICONS.search}</span>
            <input data-part="search-input" type="text" placeholder="${escapeHtml(placeholder)}" autocomplete="off" spellcheck="false" />
          </div>
        </div>
        <div data-part="body">
          <p data-part="empty-state">${escapeHtml(placeholder.replace("...", "")).trim() ? "No search history" : "No search history"}</p>
          <div data-part="results"></div>
        </div>
        <div data-part="footer">
          <div data-part="footer-hints">
            <span data-part="footer-hint">${ICONS.enter} Select</span>
            <span data-part="footer-hint">${ICONS.arrowUp} ${ICONS.arrowDown} Navigate</span>
            <span data-part="footer-hint"><span data-part="esc-key">esc</span> Close</span>
          </div>
        </div>
      </div>
    `;

    this.#modal = this.querySelector('[data-part="modal"]');
    this.#backdrop = this.querySelector('[data-part="backdrop"]');
    this.#input = this.querySelector('[data-part="search-input"]');
    this.#resultsEl = this.querySelector('[data-part="results"]');
    this.#emptyState = this.querySelector('[data-part="empty-state"]');
  }

  #bindEvents() {
    this.#onGlobalKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        this.open();
      }
    };
    window.addEventListener("keydown", this.#onGlobalKeydown);

    // Search bar triggers
    const searchBar = document.querySelector("#text-input-types-search");
    if (searchBar) {
      searchBar.addEventListener("focus", (e) => {
        e.preventDefault();
        e.target.blur();
        this.open();
      });
    }

    const searchBarWrapper = document.querySelector(
      '.noora-text-input:has(#text-input-types-search) [data-part="wrapper"]',
    );
    if (searchBarWrapper) {
      searchBarWrapper.addEventListener("click", (e) => {
        e.preventDefault();
        this.open();
      });
    }

    const mobileSearchBtn = document.querySelector('#docs-nav [data-part="mobile-actions"] button:first-child');
    if (mobileSearchBtn) {
      mobileSearchBtn.addEventListener("click", (e) => {
        e.preventDefault();
        this.open();
      });
    }

    // Backdrop
    this.#backdrop.addEventListener("click", () => this.#close());

    // Input
    this.#input.addEventListener("input", (e) => {
      clearTimeout(this.#debounceTimer);
      this.#debounceTimer = setTimeout(() => this.#search(e.target.value), 200);
    });

    this.#input.addEventListener("keydown", (e) => {
      switch (e.key) {
        case "ArrowDown":
          e.preventDefault();
          this.#moveSelection(1);
          break;
        case "ArrowUp":
          e.preventDefault();
          this.#moveSelection(-1);
          break;
        case "Enter":
          e.preventDefault();
          this.#selectCurrent();
          break;
        case "Escape":
          e.preventDefault();
          this.#close();
          break;
      }
    });
  }

  #close() {
    this.#modal.removeAttribute("data-state");
    this.#backdrop.removeAttribute("data-state");
    document.body.style.overflow = "";
    this.#input.value = "";
    this.#results = [];
    this.#selectedIndex = -1;
    this.#renderResults([]);
  }

  async #search(query) {
    if (!query || query.length < 2) {
      this.#results = [];
      this.#selectedIndex = -1;
      this.#renderResults([]);
      return;
    }

    const locale = this.getAttribute("locale") || document.documentElement.lang || "en";

    try {
      const response = await this.#client.multiSearch.perform({
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
      this.#results = [];

      response.results.forEach((result, idx) => {
        const col = COLLECTIONS[idx];
        const hits = col.groupBy
          ? (result.grouped_hits || []).map((g) => g.hits[0]).filter(Boolean)
          : result.hits || [];

        if (hits.length > 0) {
          grouped.push({ ...col, hits });
          for (const hit of hits) {
            this.#results.push({ hit, collection: col });
          }
        }
      });

      this.#selectedIndex = this.#results.length > 0 ? 0 : -1;
      this.#renderResults(grouped, query);
    } catch (err) {
      console.error("Search error:", err);
    }
  }

  #renderResults(grouped, query = "") {
    if (grouped.length === 0) {
      this.#resultsEl.innerHTML = "";
      this.#emptyState.textContent = this.#input.value.length >= 2 ? "No results found" : "No search history";
      this.#emptyState.style.display = "";
      return;
    }

    this.#emptyState.style.display = "none";
    let flatIndex = 0;
    let html = "";

    for (const group of grouped) {
      html += `<div data-part="result-group">`;
      html += `<p data-part="group-label">${ICONS[group.icon] || ""}<span>${escapeHtml(group.label)}</span></p>`;

      for (const hit of group.hits) {
        const title = titleFor(hit);
        const subtitle = subtitleFor(hit);
        const url = urlFor(hit);
        const selected = flatIndex === this.#selectedIndex;
        const target = group.external ? ' target="_blank" rel="noopener noreferrer"' : "";

        html += `<a href="${escapeHtml(url)}" data-part="result-item" data-index="${flatIndex}"${selected ? ' data-selected=""' : ""}${target}>`;
        html += `<span data-part="result-text">`;
        html += `<span data-part="result-title">${highlightMatch(title, query)}</span>`;
        if (subtitle && subtitle !== title) {
          html += `<span data-part="result-subtitle">${escapeHtml(subtitle)}</span>`;
        }
        html += `</span>`;
        html += `<span data-part="result-enter">${ICONS.enter}</span>`;
        html += `</a>`;
        flatIndex++;
      }

      html += `</div>`;
    }

    this.#resultsEl.innerHTML = html;

    for (const item of this.#resultsEl.querySelectorAll('[data-part="result-item"]')) {
      item.addEventListener("mouseenter", () => {
        this.#selectedIndex = parseInt(item.dataset.index, 10);
        this.#updateSelection();
      });
    }
  }

  #moveSelection(direction) {
    if (this.#results.length === 0) return;
    this.#selectedIndex = (this.#selectedIndex + direction + this.#results.length) % this.#results.length;
    this.#updateSelection();
  }

  #updateSelection() {
    for (const [idx, item] of this.#resultsEl.querySelectorAll('[data-part="result-item"]').entries()) {
      if (idx === this.#selectedIndex) {
        item.setAttribute("data-selected", "");
        item.scrollIntoView({ block: "nearest" });
      } else {
        item.removeAttribute("data-selected");
      }
    }
  }

  #selectCurrent() {
    if (this.#selectedIndex < 0 || this.#selectedIndex >= this.#results.length) return;
    const { hit, collection } = this.#results[this.#selectedIndex];
    const url = urlFor(hit);
    this.#close();
    if (collection.external) {
      window.open(url, "_blank", "noopener,noreferrer");
    } else {
      window.location.href = url;
    }
  }
}

customElements.define("docs-search", DocsSearchElement);
