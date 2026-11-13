const filterKeys = ["is", "project", "branch", "commit", "status", "date", "pr"];

// This only drives local navigation and completion. The server validates the
// complete query and applies every filter before limiting database results.
export function queryParts(query) {
  const filters = {};
  const terms = [];
  let valid = (query.match(/"/g)?.length ?? 0) % 2 === 0;
  for (const [token] of query.matchAll(/(?:[^\s"]+|"[^"]*")+/g)) {
    const filter = token.match(/^([a-z_]+):(.*)$/i);
    if (filter && !/^https?:/i.test(token)) {
      const key = filter[1].toLowerCase();
      const value = filter[2].replace(/^"|"$/g, "");
      if (!filterKeys.includes(key) || !value || filters[key] !== undefined) valid = false;
      filters[key] = value;
    } else {
      terms.push(token.replace(/^"|"$/g, ""));
    }
  }
  return { filters, terms, valid };
}

export function matchingPages(pages, query) {
  const { terms } = queryParts(query);
  const term = terms.join(" ").toLocaleLowerCase();
  return pages
    .filter((page) =>
      terms.every((word) =>
        `${page.title} ${page.hierarchy ?? ""} ${page.description} ${page.keywords ?? ""} ${page.project ?? ""} ${page.path}`
          .toLocaleLowerCase()
          .includes(word.toLocaleLowerCase()),
      ),
    )
    .map((page) => ({
      ...page,
      score:
        page.path === query || page.title.toLocaleLowerCase() === term
          ? 0
          : page.title.toLocaleLowerCase().startsWith(term)
            ? 1
            : 2,
    }))
    .sort((a, b) => a.score - b.score || Number(Boolean(a.current)) - Number(Boolean(b.current)))
    .slice(0, 10);
}

export function projectDestinations(projects, preferred, explicit) {
  const target = explicit ?? preferred;
  const selected = projects.find((project) => project.name.toLocaleLowerCase() === target?.toLocaleLowerCase());
  if (explicit && !selected) return [];
  const destinations = new Map();
  for (const project of selected ? [selected, ...projects] : projects) {
    for (const page of project.pages) {
      if (destinations.has(page.destination)) continue;
      if (explicit && project !== selected) continue;
      destinations.set(page.destination, {
        ...page,
        project: project === selected ? project.name : null,
        path: project === selected ? page.path : null,
      });
    }
  }
  return [...destinations.values()];
}

export function filterSuggestions(query, caret, definitions, projects) {
  const tokens = [...query.matchAll(/(?:[^\s"]+|"[^"]*")+/g)];
  const token = tokens.find((match) => match.index <= caret && match.index + match[0].length >= caret);
  const start = token?.index ?? caret;
  const end = start + (token?.[0].length ?? 0);
  const value = query.slice(start, caret);
  if (!value || !/^[a-z]+:?[^\s]*$/i.test(value)) return [];
  const used = queryParts(query.slice(0, start) + query.slice(end)).filters;
  const values = {
    is: ["page", "project", "test-case", "test-run", "build", "preview"],
    project: projects.map((project) => project.name),
    status: ["failed", "passed", "running"],
    date: ["today", "yesterday", new Date().toISOString().slice(0, 10)],
  };
  const match = value.match(/^(is|project|status|date):(.*)$/i);
  const candidates = match
    ? (values[match[1].toLowerCase()] ?? []).map((item) => ({
        value: `${match[1].toLowerCase()}:${/\s/.test(item) ? `"${item}"` : item}`,
        description: definitions.find((definition) => definition.key === match[1].toLowerCase()).description,
      }))
    : definitions
        .filter((definition) => !used[definition.key])
        .map((definition) => ({
          value: `${definition.key}:`,
          description: `${definition.example} · ${definition.description}`,
        }));
  return candidates
    .filter(
      (item) =>
        item.value.replaceAll('"', "").toLocaleLowerCase().startsWith(value.replaceAll('"', "").toLocaleLowerCase()) &&
        item.value !== value,
    )
    .slice(0, 7)
    .map((item) => ({
      type: "filter",
      title: item.value,
      subtitle: item.description,
      query: query.slice(0, start) + item.value + query.slice(end),
      caret: start + item.value.length,
    }));
}

export function navigationStep(event) {
  if (event.isComposing || event.metaKey || event.altKey) return 0;
  if (event.key === "ArrowDown") return 1;
  if (event.key === "ArrowUp") return -1;
  return 0;
}

export function searchShortcut(event) {
  return (
    !event.repeat &&
    !event.isComposing &&
    !event.altKey &&
    !event.shiftKey &&
    Boolean(event.metaKey || event.ctrlKey) &&
    event.key.toLowerCase() === "k" &&
    !event.target?.closest?.(".xterm, #runner-shell-terminal, #runner-vnc-client, canvas, [data-terminal]")
  );
}

export default {
  mounted() {
    this.dialog = this.el.querySelector("dialog");
    this.input = this.el.querySelector("input");
    this.placeholder = this.input.placeholder;
    this.list = this.el.querySelector("[role=listbox]");
    this.status = this.el.querySelector("[role=status]");
    this.empty = this.el.querySelector("[data-part=search-empty]");
    this.error = this.el.querySelector("[data-part=search-error]");
    this.validation = this.el.querySelector("[data-part=search-validation]");
    this.heading = this.el.querySelector("[data-part=picker-heading]");
    this.labels = JSON.parse(this.el.dataset.labels);
    this.filters = JSON.parse(this.el.dataset.filters);
    this.sequence = 0;
    this.items = [];
    this.resources = [];
    this.projects = [];
    this.selected = 0;
    this.syncContext();
    this.open = (event) => {
      if (this.dialog.open) return;
      this.returnFocus = event?.target?.closest?.("button") ?? document.activeElement;
      this.picker = null;
      this.input.value = "";
      this.input.placeholder = this.placeholder;
      this.resources = [];
      this.queryError = null;
      this.selected = 0;
      this.catalogLoaded = false;
      this.error.hidden = true;
      this.dialog.showModal();
      this.input.focus();
      this.loading = true;
      this.render();
      this.load();
    };
    this.stopSearch = () => {
      clearTimeout(this.timer);
      this.request?.abort();
      this.sequence++;
      this.loading = false;
    };
    this.closed = () => {
      this.stopSearch();
      this.returnFocus?.focus();
    };
    this.onInput = (event) => {
      this.stopSearch();
      this.resources = [];
      this.queryError = null;
      this.selected = 0;
      this.error.hidden = true;
      this.loading = !this.picker;
      this.render();
      if (!this.picker && !event?.isComposing) {
        this.timer = setTimeout(() => this.load(), 300);
      }
    };
    this.onKey = (event) => {
      const inputFocused = event.target === this.input;
      const inResults = this.list.contains(event.target);
      const step = this.dialog.open && (inputFocused || inResults) ? navigationStep(event) : 0;
      if (step && this.items.length) {
        event.preventDefault();
        this.selected = (this.selected + step + this.items.length) % this.items.length;
        this.select();
        if (inResults) this.items[this.selected].focus();
        this.items[this.selected].scrollIntoView({ block: "nearest" });
      } else if (searchShortcut(event)) {
        event.preventDefault();
        if (this.dialog.open) this.dialog.close();
        else this.open(event);
      } else if (this.dialog.open && !event.isComposing) {
        if (inputFocused && event.key === "Tab" && !event.shiftKey && this.items.length) {
          event.preventDefault();
          this.items[this.selected].focus();
        } else if ((inputFocused || inResults) && event.key === "Enter") {
          event.preventDefault();
          const result = this.results[this.selected];
          if (event.shiftKey && result?.destination !== undefined) this.pickProject(result);
          else this.items[this.selected]?.click();
        } else if (inResults && event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
          event.preventDefault();
          this.input.focus();
          this.input.value += event.key;
          this.onInput();
        }
      }
    };
    // Window capture runs before any document listener, so Escape closes only the
    // search and not a modal open underneath it.
    this.onEscape = (event) => {
      if (!this.dialog.open || event.isComposing || event.key !== "Escape") return;
      event.preventDefault();
      event.stopPropagation();
      if (this.picker) this.back();
      else this.dialog.close();
    };
    this.onClick = (event) => {
      if (event.target.closest("[data-close]")) this.dialog.close();
      if (event.target.closest("[data-retry]")) this.load();
      if (event.target.closest("[data-back]")) this.back();
      const item = event.target.closest("[role=option]");
      if (item) {
        this.selected = this.items.indexOf(item);
        const result = this.results[this.selected];
        if (result.type === "filter") {
          event.preventDefault();
          this.input.value = result.query;
          this.input.focus();
          this.input.setSelectionRange(result.caret, result.caret);
          this.onInput();
        } else if (result.destination !== undefined && (!result.path || event.shiftKey)) {
          event.preventDefault();
          this.pickProject(result);
        }
      }
      if (event.target === this.dialog) {
        const rect = this.dialog.getBoundingClientRect();
        if (
          event.clientX < rect.left ||
          event.clientX > rect.right ||
          event.clientY < rect.top ||
          event.clientY > rect.bottom
        ) {
          this.dialog.close();
        }
      }
    };
    this.onMove = (event) => {
      const item = event.target.closest("[role=option]");
      if (item) {
        this.selected = this.items.indexOf(item);
        this.select();
      }
    };
    this.onNavigation = () => {
      if (this.dialog.open) this.dialog.close();
    };
    document.addEventListener("dashboard-search:open", this.open);
    document.addEventListener("keydown", this.onKey);
    window.addEventListener("keydown", this.onEscape, true);
    window.addEventListener("phx:page-loading-start", this.onNavigation);
    this.input.addEventListener("input", this.onInput);
    // Inputs during an IME composition are skipped, and Chrome fires none after it.
    this.input.addEventListener("compositionend", this.onInput);
    this.dialog.addEventListener("click", this.onClick);
    this.dialog.addEventListener("close", this.closed);
    this.list.addEventListener("pointermove", this.onMove);
    this.list.addEventListener("focusin", this.onMove);
    document.querySelectorAll("[data-search-shortcut]").forEach((hint) => {
      hint.textContent = /Mac|iPhone|iPad/.test(navigator.platform) ? "⌘ K" : "Ctrl K";
    });
  },

  syncContext() {
    this.catalogLoaded = false;
    this.preferred = this.el.dataset.project || null;
    this.recentPages = [];
    try {
      if (this.preferred) localStorage.setItem(this.el.dataset.recentKey, this.preferred);
      else this.preferred = localStorage.getItem(this.el.dataset.recentKey);
      const key = `${this.el.dataset.recentKey}:pages`;
      const stored = JSON.parse(localStorage.getItem(key) || "[]");
      this.recentPages = Array.isArray(stored) ? stored.filter((path) => typeof path === "string").slice(0, 5) : [];
      const current = JSON.parse(this.el.dataset.pages).find((page) => page.path === window.location.pathname);
      if (current) {
        this.recentPages = [current.path, ...this.recentPages.filter((path) => path !== current.path)].slice(0, 5);
        localStorage.setItem(key, JSON.stringify(this.recentPages));
      }
    } catch {
      /* Browser storage is optional, never authorization. */
    }
  },

  updated() {
    this.syncContext();
  },

  async load() {
    if (this.picker) return;
    this.stopSearch();
    if (Date.now() < (this.retryAt ?? 0)) {
      this.error.hidden = false;
      this.render();
      this.error.querySelector("span").textContent = this.labels.throttled;
      return;
    }
    const sequence = this.sequence;
    this.request = new AbortController();
    this.loading = true;
    this.empty.hidden = true;
    this.status.removeAttribute("data-empty");
    this.status.setAttribute("data-loading", "");
    this.input.setAttribute("aria-busy", "true");
    this.status.textContent = this.labels.loading;
    this.error.hidden = true;
    try {
      const response = await fetch(this.el.dataset.endpoint, {
        method: "POST",
        credentials: "same-origin",
        signal: this.request.signal,
        headers: {
          "content-type": "application/json",
          accept: "application/json",
          "x-csrf-token": document.querySelector("meta[name=csrf-token]").content,
        },
        body: JSON.stringify({
          search_query: this.input.value.trim(),
          project: this.el.dataset.project,
          recent_project: this.preferred,
          catalog: !this.catalogLoaded,
        }),
      });
      if (sequence !== this.sequence || !this.dialog.open) return;
      if (response.status === 429) {
        const seconds = Number(response.headers.get("retry-after"));
        this.retryAt = Date.now() + (Number.isFinite(seconds) && seconds > 0 ? seconds : 1) * 1000;
      }
      if (!response.ok) throw new Error("Search unavailable");
      const data = await response.json();
      if (sequence !== this.sequence || !this.dialog.open) return;
      if (data.projects) {
        this.projects = data.projects;
        this.preferred = data.preferred_project;
        this.catalogLoaded = true;
      }
      this.resources = data.results;
      this.queryError = data.error;
      this.error.hidden = data.unavailable.length === 0;
      this.loading = false;
      this.render();
    } catch (error) {
      if (error.name === "AbortError" || sequence !== this.sequence || !this.dialog.open) return;
      this.error.hidden = false;
      this.resources = [];
      this.loading = false;
      this.render();
    }
    this.error.querySelector("span").textContent =
      Date.now() < (this.retryAt ?? 0) ? this.labels.throttled : this.labels.unavailable;
  },

  pickProject(result) {
    if (result?.destination === undefined) return;
    if (!this.catalogLoaded) return;
    this.stopSearch();
    this.picker = { result, query: this.input.value, selected: this.selected };
    this.input.value = "";
    this.input.placeholder = this.labels.picker_placeholder;
    this.queryError = null;
    this.error.hidden = true;
    this.selected = 0;
    this.input.focus();
    this.render();
  },

  back() {
    if (!this.picker) return;
    const { query, selected } = this.picker;
    this.picker = null;
    this.input.value = query;
    this.input.placeholder = this.placeholder;
    this.selected = selected;
    this.input.focus();
    this.render();
    this.load();
  },

  searchResults() {
    const query = this.input.value;
    const { filters, valid } = queryParts(query);
    const scope = filters.project ?? this.el.dataset.project;
    const suggestions = filterSuggestions(
      query,
      this.input.selectionStart ?? query.length,
      this.filters,
      this.projects,
    );
    const navigationOnly =
      Object.keys(filters).every((key) => ["is", "project"].includes(key)) && (!filters.is || filters.is === "page");
    let pages = [];
    if (valid && navigationOnly && !this.queryError) {
      const catalog = JSON.parse(this.el.dataset.pages);
      const current = catalog.filter((page) => page.project);
      const projects = this.catalogLoaded
        ? this.projects
        : current.length
          ? [{ name: current[0].project, pages: current }]
          : [];
      let candidates = [
        ...(scope ? projectDestinations(projects, scope, scope) : []),
        ...(!scope ? catalog.filter((page) => !page.project) : []),
      ];
      if (!query.trim()) {
        const recent = this.recentPages
          .filter((path) => path !== globalThis.location?.pathname)
          .flatMap((path) => {
            const page = candidates.find((page) => page.path === path);
            return page ? [{ ...page, group: "recent" }] : [];
          })
          .slice(0, 3);
        candidates = [...recent, ...candidates.filter((page) => !recent.some((visit) => visit.path === page.path))];
      } else {
        candidates = matchingPages(candidates, query);
      }
      pages = candidates.map((page) => ({
        ...page,
        type: "page",
        projectBadge: null,
        pageTitle: page.title,
        subtitle: page.description,
      }));
    }
    const resources =
      this.queryError || !query.trim()
        ? []
        : this.resources
            .filter((resource) => !scope || resource.type !== "project" || filters.is === "project")
            .map((resource) => ({
              ...resource,
              projectBadge: !scope && resource.type !== "project" ? resource.project : null,
            }));
    const results = [...suggestions, ...pages, ...resources];
    if (
      query.trim() &&
      Object.keys(filters).length === 0 &&
      this.labels.documentation.toLocaleLowerCase().includes(query.toLocaleLowerCase())
    ) {
      results.push({
        type: "help",
        title: this.labels.documentation,
        subtitle: "tuist.dev",
        path: this.el.dataset.documentation,
      });
    }
    return results;
  },

  render() {
    const focused = this.list.contains(document.activeElement);
    this.heading.hidden = !this.picker;
    this.heading.querySelector("button").setAttribute("aria-label", this.labels.picker_back);
    if (this.picker)
      this.heading.querySelector("span").textContent = this.labels.open_in.replace(
        "%{page}",
        this.picker.result.pageTitle,
      );
    const results = this.picker
      ? this.projects
          .flatMap((project) => {
            const page = project.pages.find((page) => page.destination === this.picker.result.destination);
            return page && project.name.toLocaleLowerCase().includes(this.input.value.toLocaleLowerCase())
              ? [{ type: "project", title: project.name, subtitle: page.title, path: page.path }]
              : [];
          })
          .slice(0, 50)
      : this.searchResults();
    this.validation.hidden =
      !this.queryError || Boolean(this.picker) || results.some((result) => result.type === "filter");
    this.validation.textContent = this.queryError || "";
    this.input.setAttribute("aria-invalid", String(!this.validation.hidden));
    const seen = new Set();
    const groups = new Map();
    for (const result of results) {
      const key = result.query ?? result.path ?? result.destination;
      if (seen.has(key)) continue;
      seen.add(key);
      const group = result.group ?? result.type;
      if (!groups.has(group)) groups.set(group, []);
      groups.get(group).push(result);
    }
    // Remove only our groups: overlays such as Amp's review widget may attach inside the listbox.
    this.list.querySelectorAll(":scope > [role=group]").forEach((group) => group.remove());
    this.results = [];
    for (const [key, group] of groups) {
      const type = group[0].type;
      const section = document.createElement("div");
      section.setAttribute("role", "group");
      const label = this.labels[key];
      section.setAttribute("aria-label", label);
      const heading = document.createElement("p");
      heading.className = "dashboard-search-group";
      heading.textContent = label;
      heading.setAttribute("aria-hidden", "true");
      section.append(heading);
      for (const result of group) {
        const link = document.createElement(result.path ? "a" : "button");
        if (result.path) link.href = result.path;
        else link.type = "button";
        link.id = `dashboard-search-result-${this.results.length}`;
        this.results.push(result);
        link.tabIndex = -1;
        link.setAttribute("role", "option");
        const icon = document.createElement("span");
        icon.className = "dashboard-search-result-icon";
        icon.setAttribute("aria-hidden", "true");
        icon.append(
          (
            this.el.querySelector(`[data-icon="${result.icon ?? type}"]`) ?? this.el.querySelector('[data-icon="page"]')
          ).content.cloneNode(true),
        );
        const text = document.createElement("span");
        text.className = "dashboard-search-result-text";
        if (result.hierarchy) {
          const hierarchy = document.createElement("span");
          hierarchy.className = "dashboard-search-hierarchy";
          hierarchy.textContent = `${result.hierarchy} ›`;
          text.append(hierarchy);
        }
        const title = document.createElement("strong");
        title.textContent = result.title;
        const subtitle = document.createElement("small");
        subtitle.textContent = result.subtitle;
        subtitle.title = result.subtitle;
        subtitle.hidden = !result.subtitle;
        text.append(title);
        if (type !== "page") text.append(subtitle);
        link.append(icon, text);
        if (result.projectBadge) {
          const badge = this.el.querySelector("[data-project-badge]").content.firstElementChild.cloneNode(true);
          badge.classList.add("dashboard-search-project");
          badge.querySelector(":scope > span").textContent = result.projectBadge;
          badge.title = result.projectBadge;
          link.append(badge);
        }
        const enter = document.createElement("span");
        enter.className = "dashboard-search-enter";
        enter.setAttribute("aria-hidden", "true");
        enter.append(this.el.querySelector("[data-enter-icon]").content.cloneNode(true));
        link.append(enter);
        section.append(link);
      }
      this.list.append(section);
    }
    this.items = [...this.list.querySelectorAll("[role=option]")];
    this.selected = Math.min(this.selected, Math.max(0, this.items.length - 1));
    this.select();
    if (focused) (this.items[this.selected] ?? this.input).focus();
    this.list.hidden = this.items.length === 0;
    this.empty.hidden = this.loading || this.items.length > 0 || !this.validation.hidden || !this.error.hidden;
    this.empty.querySelector("[data-part=title]").textContent = this.labels.empty_title.replace(
      "%{query}",
      this.input.value.trim(),
    );
    this.input.setAttribute("aria-busy", String(Boolean(this.loading)));
    this.status.toggleAttribute("data-loading", Boolean(this.loading));
    // Only show "Searching…" when there is nothing else to look at, so opening
    // the menu or refining a query with visible results does not flash it.
    this.status.toggleAttribute(
      "data-visible",
      Boolean(this.loading) && this.items.length === 0 && this.input.value.trim() !== "",
    );
    this.status.toggleAttribute("data-empty", !this.empty.hidden);
    this.status.textContent = this.loading ? this.labels.loading : !this.empty.hidden ? this.labels.empty : "";
    if (
      !this.queryError &&
      !this.picker &&
      /\b(is:(?:build|test-run)|(?:date|status|branch|commit|pr):)/.test(this.input.value)
    ) {
      this.status.textContent = [this.status.textContent, this.labels.window].filter(Boolean).join(" · ");
    }
  },

  select() {
    this.items.forEach((item, index) => item.setAttribute("aria-selected", String(index === this.selected)));
    if (this.items[this.selected]) this.input.setAttribute("aria-activedescendant", this.items[this.selected].id);
    else this.input.removeAttribute("aria-activedescendant");
  },

  destroyed() {
    this.stopSearch();
    if (this.dialog.open) this.dialog.close();
    document.removeEventListener("dashboard-search:open", this.open);
    document.removeEventListener("keydown", this.onKey);
    window.removeEventListener("keydown", this.onEscape, true);
    window.removeEventListener("phx:page-loading-start", this.onNavigation);
    this.input.removeEventListener("input", this.onInput);
    this.input.removeEventListener("compositionend", this.onInput);
    this.dialog.removeEventListener("click", this.onClick);
    this.dialog.removeEventListener("close", this.closed);
    this.list.removeEventListener("pointermove", this.onMove);
    this.list.removeEventListener("focusin", this.onMove);
  },
};
