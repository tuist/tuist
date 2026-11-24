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
    this.serverChecked = getBooleanOption(this.el, "checked");
    this.toggle = new Toggle(this.el, this.context());
    this.toggle.init();
  },

  // When the server renders a new state, follow it. Otherwise keep the
  // state people set, which the server may not track.
  updated() {
    const checked = getBooleanOption(this.el, "checked");
    if (checked !== this.serverChecked) {
      this.serverChecked = checked;
      if (checked !== this.toggle.api.checked) {
        // A state that came from the server isn't sent back to it.
        this.synced = checked;
        this.toggle.machine.send({
          type: "CHECKED.SET",
          checked,
          isTrusted: true,
        });
      }
    }
    this.toggle.render();
  },

  beforeDestroy() {
    this.toggle.destroy();
  },

  context() {
    return {
      id: this.el.id,
      // The name and value the toggle submits in a form. Without them Zag
      // clears the input's name and the field never reaches the server.
      name: this.el.getAttribute("name") || undefined,
      value: "true",
      defaultChecked: this.serverChecked,
      disabled: getBooleanOption(this.el, "disabled"),
      onCheckedChange: (details) => {
        const synced = this.synced;
        this.synced = undefined;
        if (synced !== undefined && details.checked === synced) return;
        if (this.el.dataset.onCheckedChange) {
          this.pushEvent(this.el.dataset.onCheckedChange, details);
        }
      },
    };
  },
};
