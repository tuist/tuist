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
  },

  beforeDestroy() {
    this.toggle.destroy();
  },

  context() {
    return {
      id: this.el.id,
      checked: getBooleanOption(this.el, "checked"),
      disabled: getBooleanOption(this.el, "disabled"),
      onCheckedChange: (details) => {
        if (this.el.dataset.onCheckedChange) {
          this.pushEvent(this.el.dataset.onCheckedChange, details);
        }
      },
    };
  },
};
