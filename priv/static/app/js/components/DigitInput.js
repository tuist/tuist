import * as menu from "https://cdn.jsdelivr.net/npm/@zag-js/pin-input@0.81.2/+esm";
import { normalizeProps, spreadProps, renderPart, getOption, getBooleanOption } from "./util.js";
import { Component } from "./component.js";

class PinInput extends Component {
  initService(context) {
    return menu.machine(context);
  }

  initApi() {
    return menu.connect(this.service.state, this.service.send, normalizeProps);
  }

  render() {
    const parts = ["root", "label"];
    for (const part of parts) renderPart(this.el, part, this.api);
    this.renderInputs();
  }

  renderInputs() {
    for (const input of this.el.querySelectorAll("[data-part='input']")) {
      const index = input.dataset.index;
      if (!index || Number.isNaN(Number.parseInt(index))) {
        console.error("Missing or non-integer `data-index` attribute on input.");
        return;
      }
      spreadProps(input, this.api.getInputProps({ index: Number.parseInt(index) }));
    }
  }
}

/**
 * Phoenix LiveView Hook for Digit Input component
 */
export default {
  mounted() {
    this.context = {
      id: this.el.id,
      disabled: getBooleanOption(this.el, "disabled"),
      placeholder: this.el.dataset.placeholder,
      type: getOption(this.el, "type", ["alphanumeric", "numeric", "alphabetic"]),
      otp: getBooleanOption(this.el, "otp"),
      mask: getBooleanOption(this.el, "mask"),
      blurOnComplete: getBooleanOption(this.el, "blurOnComplete"),
      onValueChange: (details) => {
        if (this.el.dataset.onChange) {
          this.pushEvent(this.el.dataset.onChange, details);
        }
      },
      onValueComplete: (details) => {
        if (this.el.dataset.onComplete) {
          this.pushEvent(this.el.dataset.onComplete, details);
        }
      },
      onValueInvalid: (details) => {
        if (this.el.dataset.onInvalid) {
          this.pushEvent(this.el.dataset.onInvalid, details);
        }
      },
    };
    this.pinInput = new PinInput(this.el, this.context);
    this.pinInput.init();
  },

  updated() {
    this.menu.render();
  },

  beforeDestroy() {
    this.menu.destroy();
  },
};
