import * as tagsInput from "@zag-js/tags-input";
import { normalizeProps, spreadProps, renderPart, getPartSelector } from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class TagsInput extends Component {
  initMachine(context) {
    return new VanillaMachine(tagsInput.machine, context);
  }

  initApi() {
    return tagsInput.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = ["root", "root:input"];
    for (const part of parts) renderPart(this.el, part, this.api);
    this.renderItems();
  }

  renderItems() {
    for (const item of this.el.querySelectorAll(getPartSelector("root:item"))) {
      const value = item.dataset.value;
      if (!value) {
        console.error("Missing `data-value` attribute on item.");
        return;
      }
      const index = item.dataset.index;
      if (!index) {
        console.error("Missing `data-index` attribute on item.");
        return;
      }

      const itemPreview = item.querySelector("[data-part='item-preview']");
      const itemDeleteTrigger = item.querySelector("[data-part='item-delete-trigger']");
      const itemInput = item.querySelector("[data-part='item-input']");

      spreadProps(item, this.api.getItemProps({ value, index }));
      if (itemPreview) spreadProps(itemPreview, this.api.getItemPreviewProps({ value, index }));
      if (itemDeleteTrigger) spreadProps(itemDeleteTrigger, this.api.getItemDeleteTriggerProps({ value, index }));
      if (itemInput) spreadProps(itemInput, this.api.getItemInputProps({ value, index }));
    }
  }
}

/**
 * Phoenix LiveView Hook for TagsInput component
 */
export default {
  mounted() {
    this.tagsInput = new TagsInput(this.el, this.context());
    this.tagsInput.init();
    this.handleEvent(`clear-tags-input-${this.el.id}`, () => {
      this.tagsInput.api.clearInputValue();
    });
  },

  updated() {
    this.tagsInput.render();
    // NOTE: Honestly don't know why this is explicitly needed, but LiveView loses complete focus of the parent otherwise.
    this.el.querySelector(getPartSelector("root:input")).focus();
  },

  beforeDestroy() {
    this.tagsInput.destroy();
  },

  context() {
    return {
      id: this.el.id,
    };
  },
};
