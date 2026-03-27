import * as dialog from "@zag-js/dialog";
import {
  getOption,
  getBooleanOption,
  normalizeProps,
  renderPart,
} from "./util.js";
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
    const parts = [
      "trigger",
      "backdrop",
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
    this.dialog = new Dialog(this.el, this.context());
    this.dialog.init();
    this.handleCloseModal = (event) => {
      if (event.detail.id == this.el.id) {
        this.dialog.api.setOpen(false);
      }
    };
    window.addEventListener("phx:close-modal", this.handleCloseModal);
    this.handleOpenModal = (event) => {
      if (event.detail.id == this.el.id) {
        this.dialog.api.setOpen(true);
      }
    };
    window.addEventListener("phx:open-modal", this.handleOpenModal);
  },

  updated() {
    this.dialog.render();
  },

  beforeDestroy() {
    this.dialog.destroy();
  },

  destroyed() {
    if (this.handleCloseModal) {
      window.removeEventListener("phx:close-modal", this.handleCloseModal);
    }
    if (this.handleOpenModal) {
      window.removeEventListener("phx:open-modal", this.handleOpenModal);
    }
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
