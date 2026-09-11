import * as tooltip from "@zag-js/tooltip";
import { getBooleanOption, normalizeProps, renderPart } from "./util.js";
import { Component } from "./component.js";
import { VanillaMachine } from "./machine.js";

class Tooltip extends Component {
  initMachine(context) {
    return new VanillaMachine(tooltip.machine, context);
  }

  initApi() {
    return tooltip.connect(this.machine.service, normalizeProps);
  }

  render() {
    const parts = ["trigger", "positioner", "content", "arrow", "arrow-tip"];
    for (const part of parts) renderPart(this.el, part, this.api);
  }

  onOpenChange(details) {
    const positioner = this.el.querySelector("[data-part='positioner']");
    if (!positioner) return;

    positioner.hidden = !details.open;
  }
}

export default {
  mounted() {
    let openDelay;
    let closeDelay;
    if (
      this.el.dataset.openDelay &&
      !Number.isNaN(Number.parseInt(this.el.dataset.openDelay))
    ) {
      openDelay = Number.parseInt(this.el.dataset.openDelay);
    }
    if (
      this.el.dataset.closeDelay &&
      !Number.isNaN(Number.parseInt(this.el.dataset.closeDelay))
    ) {
      closeDelay = Number.parseInt(this.el.dataset.closeDelay);
    }

    this.context = {
      id: this.el.id,
      openDelay: openDelay,
      closeDelay: closeDelay,
      positioning: {
        placement: this.el.dataset.positioningPlacement,
      },
      interactive: getBooleanOption(this.el, "interactive"),
      closeOnEscape: getBooleanOption(this.el, "closeOnEscape"),
      closeOnScroll: getBooleanOption(this.el, "closeOnScroll"),
      closeOnPointerDown: getBooleanOption(this.el, "closeOnPointerDown"),
      onOpenChange: (details) => {
        this.tooltip.onOpenChange(details);
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
    };
    this.tooltip = new Tooltip(this.el, this.context);
    this.tooltip.init();

    // Touch screens have no hover, and zag's tooltip opens only on hover
    // and keyboard focus, so a tap did nothing. On hover-less devices a tap
    // on the trigger toggles it and a tap anywhere else closes it. The open
    // state is read on pointerdown, before zag's own closeOnPointerDown
    // handling runs, so a tap on an open tooltip closes it instead of
    // closing and immediately reopening.
    if (window.matchMedia && window.matchMedia("(hover: none)").matches) {
      const trigger = () => this.el.querySelector("[data-part='trigger']");
      this.onPointerDown = (event) => {
        const t = trigger();
        if (t && t.contains(event.target)) {
          this.wasOpen = this.tooltip.api.open;
        } else if (this.tooltip.api.open) {
          this.tooltip.api.setOpen(false);
        }
      };
      this.onClick = (event) => {
        const t = trigger();
        if (!t || !t.contains(event.target)) return;
        event.preventDefault();
        this.tooltip.api.setOpen(!this.wasOpen);
        this.wasOpen = false;
      };
      document.addEventListener("pointerdown", this.onPointerDown, true);
      this.el.addEventListener("click", this.onClick);
    }
  },

  updated() {
    this.tooltip.render();
  },

  beforeDestroy() {
    if (this.onPointerDown)
      document.removeEventListener("pointerdown", this.onPointerDown, true);
    if (this.onClick) this.el.removeEventListener("click", this.onClick);
    this.tooltip.destroy();
  },
};
