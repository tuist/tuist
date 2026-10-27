import { copyTextToClipboard } from "../../shared/js/clipboard.js";

const COPY_PAGE_FEEDBACK_DURATION_MS = 3000;
const COPY_PAGE_FLASH_EVENT = "docs:copy-page-button:flash";

function getDocsPageMarkdown(markdownSourceId) {
  const markdown = document.getElementById(markdownSourceId);
  return markdown?.value || "";
}

function dispatchCopyPageButtonFlash() {
  window.dispatchEvent(new CustomEvent(COPY_PAGE_FLASH_EVENT));
}

const DocsCopyPageButtonHook = {
  mounted() {
    this.timeoutId = null;
    this.label = this.el.querySelector('[data-part="label"]');
    this.markdownSourceId = this.el.dataset.markdownSourceId || "docs-page-markdown";

    this.handleClick = () => {
      const markdown = getDocsPageMarkdown(this.markdownSourceId);
      if (!markdown) return;

      copyTextToClipboard(markdown)
        .then(() => this.flashCopiedLabel())
        .catch((error) => console.error("Failed to copy page:", error));
    };

    this.handleFlash = () => {
      this.flashCopiedLabel();
    };

    this.el.addEventListener("click", this.handleClick);
    window.addEventListener(COPY_PAGE_FLASH_EVENT, this.handleFlash);
  },

  destroyed() {
    this.clearTimeout();
    this.restoreDefaultLabel();
    this.el.removeEventListener("click", this.handleClick);
    window.removeEventListener(COPY_PAGE_FLASH_EVENT, this.handleFlash);
  },

  clearTimeout() {
    if (!this.timeoutId) return;

    clearTimeout(this.timeoutId);
    this.timeoutId = null;
  },

  restoreDefaultLabel() {
    if (!this.label) return;

    this.label.textContent = this.el.dataset.defaultLabel || "Copy page";
  },

  flashCopiedLabel() {
    if (!this.label) return;

    this.clearTimeout();
    this.label.textContent = this.el.dataset.copiedLabel || "Copied";

    this.timeoutId = window.setTimeout(() => {
      this.restoreDefaultLabel();
      this.timeoutId = null;
    }, COPY_PAGE_FEEDBACK_DURATION_MS);
  },
};

export { dispatchCopyPageButtonFlash };
export default DocsCopyPageButtonHook;
