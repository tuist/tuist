import * as select from "@zag-js/select";
import { getOption, getPartSelector, normalizeProps, renderPart, spreadProps } from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class Select extends Component {
  initMachine(context) {
    return new VanillaMachine(select.machine, context);
  }

  initApi() {
    return select.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = ["hidden-select", "trigger", "trigger:indicator", "positioner", "positioner:content"];
    for (const part of parts) renderPart(this.el, part, this.api);
    this.renderItems();
  }

  renderItems() {
    for (const item of this.el.querySelectorAll(getPartSelector("positioner:content:item"))) {
      const value = item.dataset.value;
      const label = item.dataset.label;
      if (!value || !label) {
        console.error("Missing `data-value` or `data-label` attribute on item.");
        return;
      }

      spreadProps(item, this.api.getItemProps({ item: { value, label } }));
    }
  }
}

export default {
  mounted() {
    this.select = new Select(this.el, this.context());
    this.select.init();
  },

  updated() {
    this.select.render();
  },

  beforeDestroy() {
    this.select.destroy();
  },

  context() {
    return {
      id: this.el.id,
      collection: this.collection(),
      name: getOption(this.el, "name"),
      // Zag.js expects the controlled value to always be an array.
      onValueChange: (details) => {
        if (this.el.dataset.onValueChange) {
          this.pushEvent(this.el.dataset.onValueChange, details);
        }
      },
    };
  },

  items() {
    return Array.from(this.el.querySelectorAll("[data-part='item']"))
      .map((item) => {
        const value = item.dataset.value;
        const label = item.dataset.label;
        if (!value || !label) {
          console.error("Missing `data-value` or `data-label` attribute on item.");
          return;
        }

        return { value, label };
      })
      .filter((value) => value !== undefined);
  },

  collection() {
    return select.collection({
      items: this.items(),
      itemToString: (item) => item.label,
      itemToValue: (item) => item.value,
    });
  },
};
