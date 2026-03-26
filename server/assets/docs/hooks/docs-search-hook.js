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

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function highlightMatch(text, query) {
  if (!text || !query) return escapeHtml(text || "");
  const escaped = escapeHtml(text);
  const regex = new RegExp(`(${query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi");
  return escaped.replace(regex, '<mark data-part="highlight">$1</mark>');
}

function resultTitle(hit) {
  const doc = hit.document;
  const h = doc.hierarchy || {};
  // Use explicit title field if available (e.g. projectdescription)
  if (doc.title) return doc.title;
  // Always use the page title (lvl0) as the primary display
  if (h.lvl0) return h.lvl0;
  for (let i = 1; i <= 6; i++) {
    if (h[`lvl${i}`]) return h[`lvl${i}`];
  }
  const content = doc.content || "";
  if (content) return content.length > 80 ? content.slice(0, 80) + "..." : content;
  return doc.url || "";
}

function resultSubtitle(hit) {
  const doc = hit.document;
  const h = doc.hierarchy || {};
  // For projectdescription, show the role as subtitle
  if (doc.role) return doc.role;
  const pageTitle = h.lvl0 || "";
  // Show the deepest section heading as subtitle (the specific match)
  for (let i = 6; i >= 1; i--) {
    if (h[`lvl${i}`] && h[`lvl${i}`] !== pageTitle) return h[`lvl${i}`];
  }
  return "";
}

function resultUrl(hit) {
  return hit.document.url_without_anchor || hit.document.url || "#";
}

function iconSvg(type) {
  if (type === "hash") {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="4" y1="9" x2="20" y2="9"/><line x1="4" y1="15" x2="20" y2="15"/><line x1="10" y1="3" x2="8" y2="21"/><line x1="16" y1="3" x2="14" y2="21"/></svg>';
  }
  if (type === "swift") {
    return '<svg width="16" height="16" viewBox="1 3 29 25" xmlns="http://www.w3.org/2000/svg"><path d="M19.422,4.007s6.217,3.554,7.844,9.2c1.466,5.1.292,7.534.292,7.534a8.915,8.915,0,0,1,1.742,2.8,4.825,4.825,0,0,1,.29,4.453s-.1-2.08-3.2-2.511c-2.841-.4-3.874,2.366-9.3,2.232A18.435,18.435,0,0,1,2,19.354C4.651,20.8,8.124,23.045,12.449,22.7s5.228-1.674,5.228-1.674A66.9,66.9,0,0,1,4.891,7.643c3.4,2.845,11.822,8.507,11.626,8.363A75.826,75.826,0,0,1,8.092,6.24S20.728,16.629,21.745,16.563c.418-.861,2.579-5.318-2.324-12.557Z" fill="#F05138"/></svg>';
  }
  if (type === "github") {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M9 19c-4.3 1.4 -4.3 -2.5 -6 -3m12 5v-3.5c0 -1 .1 -1.4 -.5 -2c2.8 -.3 5.5 -1.4 5.5 -6a4.6 4.6 0 0 0 -1.3 -3.2a4.2 4.2 0 0 0 -.1 -3.2s-1.1 -.3 -3.5 1.3a12.3 12.3 0 0 0 -6.2 0c-2.4 -1.6 -3.5 -1.3 -3.5 -1.3a4.2 4.2 0 0 0 -.1 3.2a4.6 4.6 0 0 0 -1.3 3.2c0 4.6 2.7 5.7 5.5 6c-.6 .6 -.6 1.2 -.5 2v3.5"/></svg>';
  }
  if (type === "community") {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" clip-rule="evenodd" d="M6.97872 6.54172C10.1369 4.30173 14.6947 4.49268 17.596 6.96693L6.97872 6.54172ZM17.596 6.96693C20.4502 9.4021 20.8093 13.2718 18.5023 16.0712C16.1504 18.925 11.7101 19.8354 8.13675 18.1006C7.93653 18.0034 7.7096 17.9758 7.49191 18.0221L4.50139 18.6584L5.2487 16.4164C5.34701 16.1215 5.30256 15.7976 5.12842 15.54C3.12975 12.5842 3.86507 8.75123 6.97872 6.54172M5.82147 4.91053C9.71524 2.14867 15.2853 2.36771 18.8939 5.44531C22.5496 8.56415 23.0707 13.6726 20.0457 17.3432C17.1379 20.8716 11.8714 21.9565 7.58154 20.0478L3.20813 20.9783C2.85732 21.0529 2.49341 20.934 2.25441 20.6666C2.0154 20.3991 1.93792 20.0242 2.05133 19.684L3.20102 16.2349C0.902056 12.3841 2.0244 7.60488 5.82147 4.91053Z" fill="currentColor"/></svg>';
  }
  return "";
}

function enterIconSvg() {
  return '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 10 4 15 9 20"/><path d="M20 4v7a4 4 0 0 1-4 4H4"/></svg>';
}

export function initDocsSearch() {
  const el = document.getElementById("docs-search");
  if (!el) return;

  const host = el.dataset.typesenseHost || "https://search.tuist.dev";
  const apiKey = el.dataset.typesenseApiKey || "";

  const client = new Typesense.Client({
    nodes: [{ host: new URL(host).hostname, port: 443, protocol: "https" }],
    apiKey: apiKey,
    connectionTimeoutSeconds: 5,
  });

  const modal = el.querySelector('[data-part="modal"]');
  const backdrop = el.querySelector('[data-part="backdrop"]');
  const input = el.querySelector('[data-part="search-input"]');
  const resultsContainer = el.querySelector('[data-part="results"]');
  const emptyState = el.querySelector('[data-part="empty-state"]');

  let selectedIndex = -1;
  let results = [];
  let debounceTimer = null;

  function open() {
    modal.setAttribute("data-state", "open");
    backdrop.setAttribute("data-state", "open");
    document.body.style.overflow = "hidden";
    requestAnimationFrame(() => input?.focus());
  }

  function close() {
    modal.removeAttribute("data-state");
    backdrop.removeAttribute("data-state");
    document.body.style.overflow = "";
    input.value = "";
    results = [];
    selectedIndex = -1;
    renderResults([]);
  }

  async function search(query) {
    if (!query || query.length < 2) {
      results = [];
      selectedIndex = -1;
      renderResults([]);
      return;
    }

    const locale = document.documentElement.lang || "en";

    try {
      const searchRequests = {
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
      };

      const response = await client.multiSearch.perform(searchRequests);
      const grouped = [];
      results = [];

      response.results.forEach((result, idx) => {
        const col = COLLECTIONS[idx];
        let hits;
        if (col.groupBy) {
          const groups = result.grouped_hits || [];
          hits = groups.map((g) => g.hits[0]).filter(Boolean);
        } else {
          hits = result.hits || [];
        }
        if (hits.length > 0) {
          grouped.push({ ...col, hits });
          hits.forEach((hit) => {
            results.push({ hit, collection: col });
          });
        }
      });

      selectedIndex = results.length > 0 ? 0 : -1;
      renderResults(grouped, query);
    } catch (err) {
      console.error("Search error:", err);
    }
  }

  function renderResults(grouped, query = "") {
    if (!resultsContainer) return;

    if (grouped.length === 0) {
      resultsContainer.innerHTML = "";
      if (input?.value?.length >= 2) {
        emptyState.textContent = "No results found";
        emptyState.style.display = "";
      } else {
        emptyState.textContent = "No search history";
        emptyState.style.display = "";
      }
      return;
    }

    emptyState.style.display = "none";

    let flatIndex = 0;
    let html = "";

    for (const group of grouped) {
      html += `<div data-part="result-group">`;
      html += `<p data-part="group-label">${iconSvg(group.icon)}<span>${escapeHtml(group.label)}</span></p>`;

      for (const hit of group.hits) {
        const title = resultTitle(hit);
        const subtitle = resultSubtitle(hit);
        const url = resultUrl(hit);
        const isSelected = flatIndex === selectedIndex;
        const showSubtitle = subtitle && subtitle !== title;

        const targetAttr = group.external ? ' target="_blank" rel="noopener noreferrer"' : "";
        html += `<a href="${escapeHtml(url)}" data-part="result-item" data-index="${flatIndex}" ${isSelected ? 'data-selected=""' : ""}${targetAttr}>`;
        html += `<span data-part="result-text">`;
        html += `<span data-part="result-title">${highlightMatch(title, query)}</span>`;
        if (showSubtitle) {
          html += `<span data-part="result-subtitle">${escapeHtml(subtitle)}</span>`;
        }
        html += `</span>`;
        html += `<span data-part="result-enter">${enterIconSvg()}</span>`;
        html += `</a>`;
        flatIndex++;
      }

      html += `</div>`;
    }

    resultsContainer.innerHTML = html;

    resultsContainer.querySelectorAll('[data-part="result-item"]').forEach((item) => {
      item.addEventListener("mouseenter", () => {
        selectedIndex = parseInt(item.dataset.index, 10);
        updateSelection();
      });
    });
  }

  function moveSelection(direction) {
    if (results.length === 0) return;
    selectedIndex = (selectedIndex + direction + results.length) % results.length;
    updateSelection();
  }

  function updateSelection() {
    resultsContainer?.querySelectorAll('[data-part="result-item"]').forEach((item, idx) => {
      if (idx === selectedIndex) {
        item.setAttribute("data-selected", "");
        item.scrollIntoView({ block: "nearest" });
      } else {
        item.removeAttribute("data-selected");
      }
    });
  }

  function selectCurrent() {
    if (selectedIndex < 0 || selectedIndex >= results.length) return;
    const { hit, collection } = results[selectedIndex];
    const url = resultUrl(hit);
    close();
    if (collection.external) {
      window.open(url, "_blank", "noopener,noreferrer");
    } else {
      window.location.href = url;
    }
  }

  // Global Cmd+K / Ctrl+K
  window.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault();
      open();
    }
  });

  // Search bar click/focus
  const searchBar = document.querySelector("#text-input-types-search");
  if (searchBar) {
    searchBar.addEventListener("focus", (e) => {
      e.preventDefault();
      e.target.blur();
      open();
    });
  }
  const searchBarWrapper = document.querySelector(
    '.noora-text-input:has(#text-input-types-search) [data-part="wrapper"]',
  );
  if (searchBarWrapper) {
    searchBarWrapper.addEventListener("click", (e) => {
      e.preventDefault();
      open();
    });
  }

  // Mobile search button
  const mobileSearchBtn = document.querySelector('#docs-nav [data-part="mobile-actions"] button:first-child');
  if (mobileSearchBtn) {
    mobileSearchBtn.addEventListener("click", (e) => {
      e.preventDefault();
      open();
    });
  }

  // Backdrop close
  backdrop?.addEventListener("click", () => close());

  // Search input
  input?.addEventListener("input", (e) => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => search(e.target.value), 200);
  });

  // Keyboard navigation
  input?.addEventListener("keydown", (e) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      moveSelection(1);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      moveSelection(-1);
    } else if (e.key === "Enter") {
      e.preventDefault();
      selectCurrent();
    } else if (e.key === "Escape") {
      e.preventDefault();
      close();
    }
  });
}
