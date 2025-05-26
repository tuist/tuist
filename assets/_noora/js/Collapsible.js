import * as collapsible from "@zag-js/collapsible";
import { getBooleanOption, normalizeProps, renderPart, getPartSelector, spreadProps } from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class Collapsible extends Component {
  initMachine(context) {
    return new VanillaMachine(collapsible.machine, context);
  }

  initApi() {
    return collapsible.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = ["root", "root:trigger", "root:content"];
    for (const part of parts) renderPart(this.el, part, this.api);
  }
}

export default {
  mounted() {
    this.collapsible = new Collapsible(this.el, this.context());
    this.collapsible.init();
  },

  updated() {
    this.collapsible.render();
  },

  beforeDestroy() {
    this.collapsible.destroy();
  },

  context() {
    return {
      id: this.el.id,
      disabled: getBooleanOption(this.el, "disabled"),
      defaultOpen: getBooleanOption(this.el, "open"),
      onOpenChange: (details) => {
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
    };
  },
};
