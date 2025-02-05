import * as dialog from "https://cdn.jsdelivr.net/npm/@zag-js/dialog@0.81.2/+esm";
import {
  getOption,
  getBooleanOption,
  normalizeProps,
  renderPart,
} from "./util.js";
import { Component } from "./component.js";

class Dialog extends Component {
  initService(context) {
    return dialog.machine(context);
  }

  initApi() {
    return dialog.connect(
      this.service.state,
      this.service.send,
      normalizeProps,
    );
  }

  render() {
    const parts = [
      "trigger",
      "backdrop",
      "positioner",
      "content",
      "title",
      "description",
      "close-trigger",
    ];
    for (const part of parts) renderPart(this.el, part, this.api);
  }
}

export default {
  mounted() {
    this.dialog = new Dialog(this.el, this.context());
    this.dialog.init();
    this.handleEvent(`close-modal-${this.el.id}`, () =>
      this.dialog.api.setOpen(false),
    );
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
      closeOnInteractOutside: getBooleanOption(
        this.el,
        "closeOnInteractOutside",
      ),
      closeOnEscape: getBooleanOption(this.el, "closeOnEscape"),
      onOpenChange: (details) => {
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
    };
  },
};
