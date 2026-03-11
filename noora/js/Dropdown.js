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
    this.renderItemGroupLabels();
    this.renderItemGroups();
    this.renderItems();
    this.renderSeparators();
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

    for (const item of content.querySelectorAll('[data-part="item"]')) {
      const value = item.dataset.value;
      if (!value) {
        console.error("Missing `data-value` attribute on item.");
        return;
      }

      // Skip spreading props if item is inside breadcrumbs as that leads to issues on LiveView >= 1.1 due to conflicting state management between LiveView and JS layers.
      if (item.closest(".noora-breadcrumbs")) {
        continue;
      }

      spreadProps(item, this.api.getItemProps({ value }));
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

    for (const key in this.el.dataset) {
      if (key.startsWith("meta")) {
        const metaKey = key.charAt(4).toLowerCase() + key.slice(5);
        this.metadata[metaKey] = this.el.dataset[key];
      }
    }

    this.context = {
      id: this.el.id,
      loopFocus: getBooleanOption(this.el, "loopFocus"),
      closeOnSelect: getBooleanOption(this.el, "closeOnSelect"),
      typeahead: getBooleanOption(this.el, "typeahead"),
      positioning: {
        offset: { mainAxis: getOption(this.el, "positioningOffsetMainAxis") },
      },
      onOpenChange: (details) => {
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
      onHighlightChange: (details) => {
        if (this.el.dataset.onHighlightChange) {
          this.pushEvent(this.el.dataset.onHighlightChange, details);
        }
      },
      onSelect: (details) => {
        if (this.el.dataset.onSelect) {
          this.pushEvent(this.el.dataset.onSelect, {
            ...this.metadata,
            ...details,
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

    this.handleOpenDropdown = (event) => {
      if (event.detail.id == this.el.id) {
        this.menu.api.setOpen(true);
      }
    };
    this.handleCloseDropdown = (event) => {
      if (event.detail.all || event.detail.id === this.el.id) {
        this.menu.api.setOpen(false);
      }
    };
    window.addEventListener("phx:open-dropdown", this.handleOpenDropdown);
    window.addEventListener("phx:close-dropdown", this.handleCloseDropdown);
  },

  updated() {
    this.menu.render();
  },

  beforeDestroy() {
    this.menu.destroy();
  },

  destroyed() {
    window.removeEventListener("phx:open-dropdown", this.handleOpenDropdown);
    window.removeEventListener("phx:close-dropdown", this.handleCloseDropdown);
  },
};
