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

const hiddenInput = (el) => el.querySelector('[data-part="hidden-input"]');

// The state the server rendered: indeterminate wins over checked, as in
// Noora.CheckboxControl. Markup that renders its own checkbox input says
// it with the input's `checked` attribute.
const serverState = (el, ownInput) =>
  getBooleanOption(el, "indeterminate")
    ? "indeterminate"
    : getBooleanOption(el, "defaultChecked") ||
      (ownInput && hiddenInput(el).hasAttribute("checked"));

export default {
  mounted() {
    this.pending = 0;
    // Read before Zag takes over the input's attributes.
    this.ownInput = hiddenInput(this.el)?.type === "checkbox";
    this.serverState = serverState(this.el, this.ownInput);
    this.checkbox = new Checkbox(this.el, this.context());
    this.checkbox.init();
  },

  // When the server renders a new state, such as a select-all checkbox
  // whose group changed, follow it. Otherwise keep the state people set,
  // which the server may not track.
  updated() {
    const state = serverState(this.el, this.ownInput);
    const changed = state !== this.serverState;
    this.serverState = state;
    if (changed) this.follow(state);
    else this.reconcile();
    this.checkbox.render();
  },

  // A checkbox that reports its changes belongs to the server: when the
  // server keeps the state it had, having turned a change down, go back to
  // it. Not while a change is on its way, though, or a re-render that
  // lands before the server's answer would flick the box back.
  reconcile() {
    if (this.pending > 0 || !this.el.dataset.onCheckedChange) return;
    this.follow(this.serverState);
  },

  follow(state) {
    const { api } = this.checkbox;
    if (state === (api.indeterminate ? "indeterminate" : api.checked)) return;
    this.synced = state;
    // Straight to the machine: the API's setChecked fires a click on the
    // hidden input, whose handler reads a boolean and would turn
    // indeterminate into unchecked.
    this.checkbox.machine.send({
      type: "CHECKED.SET",
      checked: state,
      isTrusted: true,
    });
  },

  // Sends a change to the server and, once it has answered (its re-render
  // is applied by then), settles on the state it rendered.
  report(details) {
    const reply = this.pushEvent(this.el.dataset.onCheckedChange, details);
    if (typeof reply?.then !== "function") return;
    this.pending += 1;
    const settle = () => {
      this.pending -= 1;
      if (this.checkbox) this.reconcile();
    };
    reply.then(settle, settle);
  },

  beforeDestroy() {
    this.checkbox.destroy();
    this.checkbox = undefined;
  },

  context() {
    // The name and value the checkbox submits in a form. Noora.Checkbox
    // puts the name on the root; markup with its own input keeps the
    // input's. Without them Zag clears the input's name and the field
    // never reaches the server.
    const input = hiddenInput(this.el);
    return {
      id: this.el.id,
      name: this.el.getAttribute("name") || input?.getAttribute("name"),
      value: input?.getAttribute("value") || "true",
      required: input?.hasAttribute("required"),
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
        if (this.el.dataset.onCheckedChange) this.report(details);
      },
    };
  },
};
