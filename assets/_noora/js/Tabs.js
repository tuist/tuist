import * as tabs from "@zag-js/tabs";
import { normalizeProps, spreadProps, renderPart, getOption } from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class Tabs extends Component {
  initMachine(context) {
    return new VanillaMachine(tabs.machine, context);
  }

  initApi() {
    return tabs.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = ["root", "list"];
    for (const part of parts) renderPart(this.el, part, this.api);
    this.renderTriggers();
    this.renderContents();
  }

  renderTriggers() {
    for (const trigger of this.el.querySelectorAll("[data-part='trigger']")) {
      const value = trigger.dataset.value;
      if (!value) {
        console.error("Missing `data-value` attribute on trigger.");
        return;
      }
      spreadProps(trigger, this.api.getTriggerProps({ value: value }));
    }
  }

  renderContents() {
    for (const content of this.el.querySelectorAll("[data-part='content']")) {
      const value = content.dataset.value;
      if (!value) {
        console.error("Missing `data-value` attribute on content.");
        return;
      }
      spreadProps(content, this.api.getContentProps({ value }));
    }
  }
}

/**
 * Phoenix LiveView Hook for Tabs component
 */
export default {
  mounted() {
    this.tabs = new Tabs(this.el, this.context());
    this.tabs.init();
  },

  updated() {
    this.tabs.render();
  },

  beforeDestroy() {
    this.tabs.destroy();
  },

  context() {
    return {
      id: this.el.id,
      defaultValue: getOption(this.el, "defaultValue"),
    };
  },
};
