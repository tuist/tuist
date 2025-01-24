import * as menu from "https://cdn.jsdelivr.net/npm/@zag-js/menu@0.81.2/+esm";
import {
  normalizeProps,
  spreadProps,
  renderPart,
  getBooleanOption,
} from "./util.js";
import { Component } from "./component.js";

class Menu extends Component {
  initService(context) {
    return menu.machine(context);
  }

  initApi() {
    return menu.connect(this.service.state, this.service.send, normalizeProps);
  }

  render() {
    const parts = ["trigger", "indicator", "positioner", "content"];
    for (const part of parts) renderPart(this.el, part, this.api);
    this.renderItemGroupLabels();
    this.renderItemGroups();
    this.renderItems();
    this.renderSeparators();
  }

  renderItemGroupLabels() {
    for (const itemGroupLabel of this.el.querySelectorAll(
      "[data-part='item-group-label']",
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
      "[data-part='item-group']",
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
    for (const item of this.el.querySelectorAll("[data-part='item']")) {
      const value = item.dataset.value;
      if (!value) {
        console.error("Missing `data-value` attribute on item.");
        return;
      }
      spreadProps(item, this.api.getItemProps({ value }));
    }
  }

  renderSeparators() {
    for (const separator of this.el.querySelectorAll(
      "[data-part='separator']",
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
    this.context = {
      id: this.el.id,
      loopFocus: getBooleanOption(this.el, "loopFocus"),
      closeOnSelect: getBooleanOption(this.el, "closeOnSelect"),
      typeahead: getBooleanOption(this.el, "typeahead"),
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
          this.pushEvent(this.el.dataset.onSelect, details);
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
  },

  updated() {
    this.menu.render();
  },

  beforeDestroy() {
    this.menu.destroy();
  },
};
