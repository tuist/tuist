import * as select from "@zag-js/select";
import {
  getBooleanOption,
  getOption,
  getPartSelector,
  normalizeProps,
  renderPart,
  spreadProps,
} from "./util.js";
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
    const parts = [
      "hidden-select",
      "trigger",
      "trigger:indicator",
      "positioner",
      "positioner:content",
    ];
    for (const part of parts) renderPart(this.el, part, this.api);
    this.renderItems();
    this.renderTriggerLabel();
  }

  renderTriggerLabel() {
    // Zag keeps the hidden <select> and item states in sync, but nothing
    // updates the visible trigger label when the user picks an option.
    // Mirror `api.valueAsString` into the trigger's label span so the
    // displayed value tracks the selection.
    const label = this.el.querySelector(
      "[data-part='trigger'] [data-part='label-wrapper'] [data-part='label']",
    );
    if (!label) return;
    const selectedLabel = this.api.valueAsString;
    const placeholder = label.dataset.placeholder || label.textContent;
    if (!label.dataset.placeholder) label.dataset.placeholder = placeholder;
    label.textContent = selectedLabel || label.dataset.placeholder;
  }

  renderItems() {
    for (const item of this.el.querySelectorAll(
      getPartSelector("positioner:content:item"),
    )) {
      const value = item.dataset.value;
      const label = item.dataset.label;
      if (!value || !label) {
        console.error(
          "Missing `data-value` or `data-label` attribute on item.",
        );
        return;
      }

      spreadProps(item, this.api.getItemProps({ item: { value, label } }));
    }
  }
}

export default {
  mounted() {
    this.serverValue = this.el.dataset.value || "";
    const context = this.context();
    this.configuration = JSON.stringify([
      context.disabled,
      context.collection.items,
    ]);
    this.select = new Select(this.el, context);
    this.select.init();
  },

  updated() {
    const value = this.el.dataset.value || "";
    const context = this.context();
    const configuration = JSON.stringify([
      context.disabled,
      context.collection.items,
    ]);
    const selected =
      value !== this.serverValue ? context.defaultValue : this.select.api.value;
    if (configuration !== this.configuration) {
      // VanillaMachine captures props at construction. Rebuild only when options
      // or disabled state change, preserving choices not yet echoed by the server.
      this.select.destroy();
      this.select = new Select(this.el, { ...context, defaultValue: selected });
      this.select.init();
    } else if (this.select.api.value.join() !== selected.join()) {
      this.select.api.setValue(selected);
    }
    this.configuration = configuration;
    this.serverValue = value;
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
      disabled: getBooleanOption(this.el, "disabled"),
      defaultValue: this.el.dataset.value ? [this.el.dataset.value] : [],
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
          console.error(
            "Missing `data-value` or `data-label` attribute on item.",
          );
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
