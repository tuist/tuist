import * as tooltip from "https://cdn.jsdelivr.net/npm/@zag-js/tooltip@0.81.2/+esm";
import { getBooleanOption, normalizeProps, renderPart } from "./util.js";
import { Component } from "./component.js";

class Tooltip extends Component {
  initService(context) {
    return tooltip.machine(context);
  }

  initApi() {
    return tooltip.connect(this.service.state, this.service.send, normalizeProps);
  }

  render() {
    const parts = ["trigger", "positioner", "content", "arrow", "arrow-tip"];
    for (const part of parts) renderPart(this.el, part, this.api);
  }

  onOpenChange(details) {
    const positioner = this.el.querySelector("[data-part='positioner']");
    if (!positioner) return;

    positioner.hidden = !details.open;
  }
}

export default {
  mounted() {
    let openDelay;
    let closeDelay;
    if (this.el.dataset.openDelay && !Number.isNaN(Number.parseInt(this.el.dataset.openDelay))) {
      openDelay = Number.parseInt(this.el.dataset.openDelay);
    }
    if (this.el.dataset.closeDelay && !Number.isNaN(Number.parseInt(this.el.dataset.closeDelay))) {
      closeDelay = Number.parseInt(this.el.dataset.closeDelay);
    }

    this.context = {
      id: this.el.id,
      openDelay: openDelay,
      closeDelay: closeDelay,
      positioning: {
        placement: this.el.dataset.positioningPlacement,
      },
      interactive: getBooleanOption(this.el, "interactive"),
      closeOnEscape: getBooleanOption(this.el, "closeOnEscape"),
      closeOnScroll: getBooleanOption(this.el, "closeOnScroll"),
      closeOnPointerDown: getBooleanOption(this.el, "closeOnPointerDown"),
      onOpenChange: (details) => {
        this.tooltip.onOpenChange(details);
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
    };
    this.tooltip = new Tooltip(this.el, this.context);
    this.tooltip.init();
  },

  updated() {
    this.tooltip.render();
  },

  beforeDestroy() {
    this.tooltip.destroy();
  },
};
