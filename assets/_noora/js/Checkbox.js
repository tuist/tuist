import * as checkbox from "@zag-js/checkbox";
import { getBooleanOption, normalizeProps, renderPart } from "./util.js";
import { Component } from "./component.js";

class Checkbox extends Component {
  initService(context) {
    return checkbox.machine(context);
  }

  initApi() {
    return checkbox.connect(this.service.state, this.service.send, normalizeProps);
  }

  render() {
    const parts = ["root", "control", "label", "hidden-input"];
    for (const part of parts) renderPart(this.el, part, this.api);
  }
}

export default {
  mounted() {
    this.checkbox = new Checkbox(this.el, this.context());
    this.checkbox.init();
  },

  updated() {
    this.checkbox.render();
  },

  beforeDestroy() {
    this.checkbox.destroy();
  },

  context() {
    return {
      id: this.el.id,
      indeterminate: getBooleanOption(this.el, "indeterminate"),
      defaultChecked: getBooleanOption(this.el, "defaultChecked"),
      disabled: getBooleanOption(this.el, "disabled"),
      onCheckChange: (details) => {
        if (this.el.dataset.onChange) {
          this.pushEvent(this.el.dataset.onCheckChange, details);
        }
      },
    };
  },
};
