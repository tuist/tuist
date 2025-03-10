import * as avatar from "@zag-js/avatar";
import { getBooleanOption, normalizeProps, renderPart } from "./util.js";
import { Component } from "./component.js";

class Avatar extends Component {
  initService(context) {
    return avatar.machine(context);
  }

  initApi() {
    return avatar.connect(this.service.state, this.service.send, normalizeProps);
  }

  render() {
    const parts = ["root", "image", "fallback"];
    for (const part of parts) renderPart(this.el, part, this.api);
  }
}

export default {
  mounted() {
    this.context = {
      id: this.el.id,
      src: this.el.dataset.src,
      srcSet: this.el.dataset.srcSet,
      name: this.el.dataset.name,
      onStatusChange: (details) => {
        if (this.el.dataset.onStatusChange) {
          this.pushEvent(this.el.dataset.onStatusChange, details);
        }
      },
    };
    this.avatar = new Avatar(this.el, this.context);
    this.avatar.init();
  },

  updated() {
    this.avatar.render();
  },

  beforeDestroy() {
    this.avatar.destroy();
  },
};
