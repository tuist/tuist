import * as popover from "@zag-js/popover";
import { getBooleanOption, normalizeProps, renderPart } from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class Popover extends Component {
  initMachine(context) {
    return new VanillaMachine(popover.machine, context);
  }

  initApi() {
    return popover.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = [
      "trigger",
      "positioner",
      "positioner:content",
      "positioner:content:title",
      "positioner:content:description",
      "positioner:content:close-trigger",
    ];
    for (const part of parts) renderPart(this.el, part, this.api);
  }
}

export default {
  mounted() {
    this.context = {
      id: this.el.id,
      modal: getBooleanOption(this.el, "modal"),
      autoFocus: getBooleanOption(this.el, "autoFocus"),
      closeOnInteractOutside: getBooleanOption(
        this.el,
        "closeOnInteractOutside",
      ),
      closeOnEscape: getBooleanOption(this.el, "closeOnEscape"),
      positioning: {
        placement: this.el.dataset.positioningPlacement,
      },
      onOpenChange: (details) => {
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
    };
    this.popover = new Popover(this.el, this.context);
    this.popover.init();

    this.handleOpenPopover = (event) => {
      if (event.detail.id == this.el.id) {
        this.popover.api.setOpen(true);
      }
    };
    this.handleClosePopover = (event) => {
      if (event.detail.all || event.detail.id === this.el.id) {
        this.popover.api.setOpen(false);
      }
    };
    window.addEventListener("phx:open-popover", this.handleOpenPopover);
    window.addEventListener("phx:close-popover", this.handleClosePopover);
  },

  updated() {
    this.popover.render();
  },

  beforeDestroy() {
    this.popover.destroy();
  },

  destroyed() {
    window.removeEventListener("phx:open-popover", this.handleOpenPopover);
    window.removeEventListener("phx:close-popover", this.handleClosePopover);
  },
};
