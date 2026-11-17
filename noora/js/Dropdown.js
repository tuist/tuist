import * as menu from "@zag-js/menu";
import {
  normalizeProps,
  spreadProps,
  renderPart,
  getBooleanOption,
  getOption,
  getPartSelector,
} from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

// Flips a Noora.Menu checkbox item: its state, which the next render reads,
// what it announces, and its checkbox.
const setMenuItemChecked = (item, checked) => {
  const state = checked ? "checked" : "unchecked";
  item.dataset.checked = String(checked);
  item.dataset.state = state;
  item.setAttribute("aria-checked", String(checked));
  const control = item.querySelector(".noora-checkbox-control");
  if (control) control.dataset.state = state;
};

class Menu extends Component {
  initMachine(context) {
    return new VanillaMachine(menu.machine, context);
  }

  initApi() {
    return menu.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = [
      "trigger",
      "trigger:indicator",
      "positioner",
      "positioner:content",
    ];
    for (const part of parts) renderPart(this.el, part, this.api);
    this.syncMenuDisabled();
    this.syncFixedPositionerSize();
    this.renderItemGroupLabels();
    this.renderItemGroups();
    this.renderItems();
    this.renderSeparators();
  }

  // Noora.Menu's root carries its disabled and empty states, which LiveView
  // keeps current even though the root ignores updates to its children. A
  // menu without items can't open; a split button's main action stays usable.
  syncMenuDisabled() {
    if (!this.el.classList.contains("noora-menu")) return;

    const disabled = this.el.hasAttribute("data-disabled");
    const empty = this.el.hasAttribute("data-empty");
    const trigger = this.el.querySelector(getPartSelector("trigger"));
    const mainButton = this.el.querySelector(getPartSelector("main-button"));

    if (trigger) trigger.disabled = disabled || empty;
    if (mainButton) mainButton.disabled = disabled;
    if ((disabled || empty) && this.api.open) this.api.setOpen(false);
  }

  syncFixedPositionerSize() {
    if (this.el.dataset.positioningStrategy !== "fixed") return;

    const positioner = this.el.querySelector(getPartSelector("positioner"));
    if (!positioner) return;

    positioner.style.minWidth = "var(--reference-width, max-content)";
  }

  renderItemGroupLabels() {
    for (const itemGroupLabel of this.el.querySelectorAll(
      getPartSelector("positioner:content:item-group-label"),
    )) {
      const htmlFor = itemGroupLabel.getAttribute("for");
      if (!htmlFor) {
        console.error("Missing `for` attribute on item group label.");
        return;
      }
      spreadProps(itemGroupLabel, this.api.getItemGroupLabelProps({ htmlFor }));
    }
  }

  renderItemGroups() {
    for (const itemGroup of this.el.querySelectorAll(
      getPartSelector("positioner:content:item-group"),
    )) {
      const value = itemGroup.dataset.value;
      if (!value) {
        console.error("Missing `data-value` attribute on item group.");
        return;
      }
      spreadProps(itemGroup, this.api.getItemGroupProps({ id: value }));
    }
  }

  renderItems() {
    const content = this.el.querySelector('[data-part="content"]');
    if (!content) return;

    const menuValues = new Set();
    for (const item of content.querySelectorAll('[data-part="item"]')) {
      const value = item.dataset.value;
      if (!value) {
        console.error("Missing `data-value` attribute on item.");
        return;
      }

      // Items are identified by value, so a repeated one would highlight and
      // select the wrong item.
      if (item.classList.contains("noora-menu-item")) {
        if (menuValues.has(value)) {
          console.warn(
            `Noora.Menu "${this.el.id}" has more than one item with value "${value}". Values must be unique within a menu.`,
          );
        }
        menuValues.add(value);
      }

      // Skip spreading props if item is inside breadcrumbs as that leads to issues on LiveView >= 1.1 due to conflicting state management between LiveView and JS layers.
      if (item.closest(".noora-breadcrumbs")) {
        continue;
      }

      const disabled = item.hasAttribute("data-disabled");
      // Noora.Menu checkbox items toggle in place and keep the menu open, so
      // several can be toggled in a row. A re-render with a new `checked`
      // from the LiveView still wins. Dropdown checkbox items keep their own
      // behavior.
      const menuCheckbox =
        item.classList.contains("noora-menu-item") &&
        item.hasAttribute("data-checkbox");
      const props = menuCheckbox
        ? this.api.getOptionItemProps({
            type: "checkbox",
            value,
            checked: item.dataset.checked === "true",
            disabled,
            closeOnSelect: false,
            onCheckedChange: (checked) => setMenuItemChecked(item, checked),
          })
        : this.api.getItemProps({ value, disabled });
      spreadProps(item, props);
    }
  }

  renderSeparators() {
    for (const separator of this.el.querySelectorAll(
      getPartSelector("positioner:content:separator"),
    )) {
      spreadProps(separator, this.api.getSeparatorProps());
    }
  }
}

/**
 * Phoenix LiveView Hook for Menu component
 */
export default {
  mounted() {
    this.metadata = {};

    // Breadcrumb dropdowns can't use zag's item props (see Menu.renderItems —
    // they conflict with LiveView's DOM patching), so they get no built-in
    // arrow-key navigation. We drive roving focus over the native <a> items
    // ourselves instead.
    this.isBreadcrumb = this.el.classList.contains("noora-breadcrumb");

    for (const key in this.el.dataset) {
      if (key.startsWith("meta")) {
        const metaKey = key.charAt(4).toLowerCase() + key.slice(5);
        this.metadata[metaKey] = this.el.dataset[key];
      }
    }

    const positioningStrategy =
      getOption(this.el, "positioningStrategy", ["absolute", "fixed"]) ||
      (this.el.closest(".noora-table") ? "fixed" : undefined);
    if (positioningStrategy) {
      this.el.dataset.positioningStrategy = positioningStrategy;
    }

    this.context = {
      id: this.el.id,
      loopFocus: getBooleanOption(this.el, "loopFocus"),
      closeOnSelect: getBooleanOption(this.el, "closeOnSelect"),
      typeahead: getBooleanOption(this.el, "typeahead"),
      positioning: {
        placement: getOption(this.el, "positioningPlacement") || "bottom-start",
        strategy: positioningStrategy,
        offset: { mainAxis: getOption(this.el, "positioningOffsetMainAxis") },
        ...(() => {
          const anchorPart = getOption(this.el, "positioningAnchor");
          if (!anchorPart) return {};
          const el = this.el;
          return {
            getAnchorRect: () => {
              // "root" anchors to the whole component, such as both halves
              // of a split button.
              const anchorEl =
                anchorPart === "root"
                  ? el
                  : el.querySelector(`[data-part="${anchorPart}"]`);
              return anchorEl ? anchorEl.getBoundingClientRect() : null;
            },
          };
        })(),
      },
      onOpenChange: (details) => {
        if (this.isBreadcrumb) this.handleBreadcrumbOpenChange(details.open);
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
      onHighlightChange: (details) => {
        this.scrollToHighlightedItem(details.highlightedValue);
        if (this.el.dataset.onHighlightChange) {
          this.pushEvent(this.el.dataset.onHighlightChange, details);
        }
      },
      onSelect: (details) => {
        if (this.el.dataset.onSelect) {
          // A Noora.Menu checkbox item also sends the state it's toggling
          // to; the select fires just before the item flips.
          const checkbox = this.el.querySelector(
            `.noora-menu-item[data-checkbox][data-value="${CSS.escape(details.value)}"]`,
          );
          this.pushEvent(this.el.dataset.onSelect, {
            ...this.metadata,
            ...details,
            ...(checkbox && { checked: checkbox.dataset.checked !== "true" }),
          });
        }
      },
      onEscapeKeyDown: (details) => {
        if (this.el.dataset.onEscapeKeyDown) {
          this.pushEvent(this.el.dataset.onEscapeKeyDown, details);
        }
      },
      onPointerDownOutside: (details) => {
        if (this.el.dataset.onPointerDownOutside) {
          this.pushEvent(this.el.dataset.onPointerDownOutside, details);
        }
      },
      onFocusOutside: (details) => {
        if (this.el.dataset.onFocusOutside) {
          this.pushEvent(this.el.dataset.onFocusOutside, details);
        }
      },
      onInteractOutside: (details) => {
        if (this.el.dataset.onInteractOutside) {
          this.pushEvent(this.el.dataset.onInteractOutside, details);
        }
      },
    };
    this.menu = new Menu(this.el, this.context);
    this.menu.init();

    this.handleSearchInput = (event) => {
      if (event.target.matches('[data-part="search-input"]')) {
        this.applySearchFilter();
      }
    };

    this.handleSearchKeydown = (event) => {
      if (event.target.matches('[data-part="search-input"]')) {
        event.stopPropagation();
      }
    };

    this.el.addEventListener("input", this.handleSearchInput);
    this.el.addEventListener("keydown", this.handleSearchKeydown);
    this.applySearchFilter();

    // Whether the highlight is moving from the keyboard; see
    // scrollToHighlightedItem.
    this.trackKeyboard = () => (this.keyboardNavigation = true);
    this.trackPointer = () => (this.keyboardNavigation = false);
    this.el.addEventListener("keydown", this.trackKeyboard, true);
    this.el.addEventListener("pointermove", this.trackPointer);

    // Portaled options can be patched after this hook's updated callback.
    const items = this.el.querySelector('[data-part="items"]');
    if (items) {
      this.itemsObserver = new MutationObserver(() => {
        this.menu.render();
        this.applySearchFilter();
      });
      this.itemsObserver.observe(items, { childList: true, subtree: true });
    }

    this.handleOpenDropdown = (event) => {
      if (event.detail.id == this.el.id) {
        this.menu.api.setOpen(true);
        window.requestAnimationFrame(() => this.applySearchFilter());
      }
    };
    this.handleCloseDropdown = (event) => {
      if (event.detail.all || event.detail.id === this.el.id) {
        this.menu.api.setOpen(false);
      }
    };
    window.addEventListener("phx:open-dropdown", this.handleOpenDropdown);
    window.addEventListener("phx:close-dropdown", this.handleCloseDropdown);

    if (this.isBreadcrumb) {
      this.breadcrumbKeydown = (event) => this.handleBreadcrumbKeydown(event);
      // Capture phase so zag's content keydown handler doesn't consume the
      // arrow keys before we move focus.
      this.el.addEventListener("keydown", this.breadcrumbKeydown, true);
      // The pointer takes over from the keyboard, so only one item looks
      // highlighted at a time.
      this.breadcrumbPointerMove = () => this.clearBreadcrumbHighlight();
      this.el.addEventListener("pointermove", this.breadcrumbPointerMove);
    }
  },

  breadcrumbItems() {
    return [...this.el.querySelectorAll('[data-part="item"]')].filter(
      (item) => item.style.display !== "none",
    );
  },

  handleBreadcrumbOpenChange(open) {
    if (open) {
      // Defer until zag has shown the positioner so the items are focusable.
      window.requestAnimationFrame(() => {
        const items = this.breadcrumbItems();
        if (!items.length) return;
        const selected = items.find((item) =>
          item.hasAttribute("data-selected"),
        );
        (selected || items[0]).focus();
      });
    } else {
      this.clearBreadcrumbHighlight();
      if (this.el.contains(document.activeElement)) {
        this.el.querySelector('[data-part="trigger"]')?.focus();
      }
    }
  },

  handleBreadcrumbKeydown(event) {
    if (!this.menu.api.open) return;
    // Don't hijack typing in a dropdown search field.
    if (event.target.matches('[data-part="search-input"]')) return;

    const items = this.breadcrumbItems();
    if (!items.length) return;

    const current = items.indexOf(document.activeElement);
    let next;

    switch (event.key) {
      case "ArrowDown":
        next = current < 0 ? 0 : (current + 1) % items.length;
        break;
      case "ArrowUp":
        next =
          current < 0
            ? items.length - 1
            : (current - 1 + items.length) % items.length;
        break;
      case "Home":
        next = 0;
        break;
      case "End":
        next = items.length - 1;
        break;
      case "Enter":
      case " ":
        // The items aren't registered with zag, so its content handler
        // swallows Enter/Space (it has no highlighted item to select) and the
        // native <a> activation never fires. Trigger the focused item's click
        // ourselves — LiveView's delegated click listener handles navigation.
        if (current < 0) return;
        event.preventDefault();
        event.stopPropagation();
        items[current].click();
        return;
      case "Tab":
        // A menu is a single tab stop: the items are tabindex="-1", so close
        // the menu and hand focus back to the trigger instead of letting Tab
        // strand focus on a now-hidden item.
        event.preventDefault();
        event.stopPropagation();
        this.menu.api.setOpen(false);
        this.el.querySelector('[data-part="trigger"]')?.focus();
        return;
      default:
        // Typeahead: jump to the item whose label matches the typed characters.
        if (
          event.key.length === 1 &&
          !event.metaKey &&
          !event.ctrlKey &&
          !event.altKey
        ) {
          event.preventDefault();
          event.stopPropagation();
          this.breadcrumbTypeahead(event.key, items);
        }
        return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.highlightBreadcrumbItem(items[next]);
  },

  // Keeps the item highlighted from the keyboard in view. zag only scrolls
  // when the content itself scrolls, and here the list inside it does. The
  // list's scroll padding sets how far from its edge the item stops. A
  // pointer highlights what's under it, which must not scroll the list.
  scrollToHighlightedItem(value) {
    if (!this.keyboardNavigation || value == null) return;
    const item = this.el.querySelector(
      `[data-part="items"] [data-part="item"][data-value="${CSS.escape(value)}"]`,
    );
    item?.scrollIntoView({ block: "nearest" });
  },

  // Moves keyboard focus to an item and marks it highlighted, the way zag
  // marks Noora.Menu items. Focus alone doesn't highlight: opening the menu
  // focuses the selected item, which shows only its check.
  highlightBreadcrumbItem(item) {
    this.clearBreadcrumbHighlight();
    item.setAttribute("data-highlighted", "");
    item.focus();
  },

  clearBreadcrumbHighlight() {
    for (const item of this.el.querySelectorAll(
      '[data-part="item"][data-highlighted]',
    )) {
      item.removeAttribute("data-highlighted");
    }
  },

  breadcrumbTypeahead(char, items) {
    clearTimeout(this.typeaheadTimer);
    this.typeaheadQuery = (this.typeaheadQuery || "") + char.toLowerCase();
    this.typeaheadTimer = setTimeout(() => {
      this.typeaheadQuery = "";
    }, 500);

    const labelOf = (item) =>
      (item.dataset.label || item.textContent || "").trim().toLowerCase();

    const match =
      items.find((item) => labelOf(item).startsWith(this.typeaheadQuery)) ||
      items.find((item) => labelOf(item).includes(this.typeaheadQuery));

    if (match) this.highlightBreadcrumbItem(match);
  },

  applySearchFilter() {
    const searchInput = this.el.querySelector('[data-part="search-input"]');
    if (!searchInput) return;

    const query = searchInput.value.toLowerCase();
    const content = this.el.querySelector('[data-part="content"]');
    if (!content) return;

    let visibleCount = 0;
    for (const item of content.querySelectorAll('[data-part="item"]')) {
      const label = (
        item.dataset.label ||
        item.textContent ||
        ""
      ).toLowerCase();
      const visible = label.includes(query);
      item.style.display = visible ? "" : "none";
      if (visible) visibleCount++;
    }

    let emptyState = content.querySelector('[data-part="search-empty"]');
    if (visibleCount === 0) {
      if (!emptyState) {
        emptyState = document.createElement("span");
        emptyState.setAttribute("data-part", "search-empty");
        emptyState.textContent = "No results";
        content.querySelector('[data-part="items"]')?.appendChild(emptyState);
      }
      emptyState.style.display = "";
    } else if (emptyState) {
      emptyState.style.display = "none";
    }
  },

  updated() {
    this.menu.render();
    this.applySearchFilter();
  },

  beforeDestroy() {
    this.itemsObserver?.disconnect();
    this.menu.destroy();
  },

  destroyed() {
    this.el.removeEventListener("input", this.handleSearchInput);
    this.el.removeEventListener("keydown", this.handleSearchKeydown);
    this.el.removeEventListener("keydown", this.trackKeyboard, true);
    this.el.removeEventListener("pointermove", this.trackPointer);
    if (this.breadcrumbKeydown) {
      this.el.removeEventListener("keydown", this.breadcrumbKeydown, true);
      this.el.removeEventListener("pointermove", this.breadcrumbPointerMove);
    }
    clearTimeout(this.typeaheadTimer);
    window.removeEventListener("phx:open-dropdown", this.handleOpenDropdown);
    window.removeEventListener("phx:close-dropdown", this.handleCloseDropdown);
  },
};
