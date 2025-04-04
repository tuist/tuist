import * as dialog from "@zag-js/dialog";
import { getOption, getBooleanOption, normalizeProps, renderPart } from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class Dialog extends Component {
  initMachine(context) {
    return new VanillaMachine(dialog.machine, context);
  }

  initApi() {
    return dialog.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = ["trigger", "backdrop", "positioner", "content", "title", "description", "close-trigger"];
    for (const part of parts) renderPart(this.el, part, this.api);
  }
}

export default {
  mounted() {
    this.dialog = new Dialog(this.el, this.context());
    this.dialog.init();
    this.handleEvent(`close-modal-${this.el.id}`, () => this.dialog.api.setOpen(false));
  },

  updated() {
    this.dialog.render();
  },

  beforeDestroy() {
    this.dialog.destroy();
  },

  context() {
    return {
      id: this.el.id,
      role: getOption(this.el, "role", ["dialog", "alertdialog"]),
      preventScroll: getBooleanOption(this.el, "preventScroll"),
      closeOnInteractOutside: getBooleanOption(this.el, "closeOnInteractOutside"),
      closeOnEscape: getBooleanOption(this.el, "closeOnEscape"),
      onOpenChange: (details) => {
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
    };
  },
};
