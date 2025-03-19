import * as collapsible from "@zag-js/collapsible";
import { getBooleanOption, normalizeProps, renderPart } from "./util.js";
import { Component } from "./component.js";

class Collapsible extends Component {
  initService(context) {
    return collapsible.machine(context);
  }

  initApi() {
    return collapsible.connect(this.service.state, this.service.send, normalizeProps);
  }

  render() {
    const parts = ["root", "trigger", "content"];
    for (const part of parts) renderPart(this.el, part, this.api);
  }
}

export default {
  mounted() {
    this.collapsible = new Collapsible(this.el, this.context());
    this.collapsible.init();
  },

  updated() {
    this.collapsible.render();
  },

  beforeDestroy() {
    this.collapsible.destroy();
  },

  context() {
    return {
      id: this.el.id,
      open: getBooleanOption(this.el, "open"),
      onOpenChange: (details) => {
        if (this.el.dataset.onOpenChange) {
          this.pushEvent(this.el.dataset.onOpenChange, details);
        }
      },
    };
  },
};
