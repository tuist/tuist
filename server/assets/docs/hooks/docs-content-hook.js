import { highlightCodeBlocks } from "../../shared/js/hooks/shiki-highlight.js";
import { setupCodeCopy } from "../../shared/js/hooks/code-copy.js";
import { setupCodeGroups } from "../../shared/js/hooks/code-group.js";

async function initializeCodeBlocks(container) {
  await highlightCodeBlocks(container);
  setupCodeCopy(container);
  setupCodeGroups(container);
}

const DocsContentHook = {
  async mounted() {
    await initializeCodeBlocks(this.el);
  },
  async updated() {
    await initializeCodeBlocks(this.el);
  },
};

export default DocsContentHook;
