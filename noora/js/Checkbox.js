import * as checkbox from "@zag-js/checkbox";
import { getBooleanOption, normalizeProps, renderPart } from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class Checkbox extends Component {
  initMachine(context) {
    return new VanillaMachine(checkbox.machine, context);
  }

  initApi() {
    return checkbox.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = ["root", "root:control", "root:label", "root:hidden-input"];
    for (const part of parts) renderPart(this.el, part, this.api);
    // Zag syncs `indeterminate` (a property, not an attribute) onto the
    // input only when the state changes; keep it right from the start, so
    // assistive tech announces a mixed state.
    const input = this.el.querySelector('[data-part="hidden-input"]');
    if (input) input.indeterminate = this.api.indeterminate;
  }
}

// The state the server rendered: indeterminate wins over checked, as in
// Noora.CheckboxControl.
const serverState = (el) =>
  getBooleanOption(el, "indeterminate")
    ? "indeterminate"
    : getBooleanOption(el, "defaultChecked");

export default {
  mounted() {
    this.serverState = serverState(this.el);
    this.checkbox = new Checkbox(this.el, this.context());
    this.checkbox.init();
  },

  // When the server renders a new state, such as a select-all checkbox
  // whose group changed, follow it. Otherwise keep the state people set,
  // which the server may not track.
  updated() {
    const state = serverState(this.el);
    if (state !== this.serverState) {
      this.serverState = state;
      this.synced = state;
      // Straight to the machine: the API's setChecked fires a click on the
      // hidden input, whose handler reads a boolean and would turn
      // indeterminate into unchecked.
      this.checkbox.machine.send({
        type: "CHECKED.SET",
        checked: state,
        isTrusted: true,
      });
    }
    this.checkbox.render();
  },

  beforeDestroy() {
    this.checkbox.destroy();
  },

  context() {
    return {
      id: this.el.id,
      // Zag takes indeterminate as a checked state, not a separate option.
      defaultChecked: this.serverState,
      disabled: getBooleanOption(this.el, "disabled"),
      onCheckedChange: (details) => {
        // A state that came from the server isn't sent back to it.
        if (this.synced !== undefined && details.checked === this.synced) {
          this.synced = undefined;
          return;
        }
        this.synced = undefined;
        if (this.el.dataset.onCheckedChange) {
          this.pushEvent(this.el.dataset.onCheckedChange, details);
        }
      },
    };
  },
};
