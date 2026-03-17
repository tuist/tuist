import * as zagSwitch from "@zag-js/switch";
import { getBooleanOption, normalizeProps, renderPart } from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class Toggle extends Component {
  initMachine(context) {
    return new VanillaMachine(zagSwitch.machine, context);
  }

  initApi() {
    return zagSwitch.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = ["root", "root:control", "root:label", "root:hidden-input"];
    for (const part of parts) renderPart(this.el, part, this.api);
  }
}

export default {
  mounted() {
    this.toggle = new Toggle(this.el, this.context());
    this.toggle.init();

    // Stop change/input events from the hidden input from bubbling to parent
    // forms. Without this, the hidden input triggers phx-change on the parent
    // form, causing the server to re-render with stale toggle state.
    this._stopFormEvent = (e) => {
      if (e.target.matches("[data-part='hidden-input']")) {
        e.stopPropagation();
      }
    };
    this.el.addEventListener("change", this._stopFormEvent);
    this.el.addEventListener("input", this._stopFormEvent);
  },

  updated() {
    this.toggle.render();
  },

  beforeDestroy() {
    this.el.removeEventListener("change", this._stopFormEvent);
    this.el.removeEventListener("input", this._stopFormEvent);
    this.toggle.destroy();
  },

  context() {
    return {
      id: this.el.id,
      defaultChecked: getBooleanOption(this.el, "checked"),
      disabled: getBooleanOption(this.el, "disabled"),
      onCheckedChange: (details) => {
        if (this.el.dataset.onCheckedChange) {
          this.pushEvent(this.el.dataset.onCheckedChange, details);
        }
      },
    };
  },
};
