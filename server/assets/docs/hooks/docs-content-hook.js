import { setupCodeCopy } from "../../shared/js/hooks/code-copy.js";
import { setupCodeGroups } from "../../shared/js/hooks/code-group.js";

function initializeCodeBlocks(container) {
  setupCodeCopy(container);
  setupCodeGroups(container);
}

const DocsContentHook = {
  mounted() {
    initializeCodeBlocks(this.el);
  },
  updated() {
    initializeCodeBlocks(this.el);
  },
};

export default DocsContentHook;
