import { copyTextToClipboard } from "../../../shared/js/clipboard.js";

export const SetupPrompt = {
  mounted() {
    this.button = this.el.querySelector('[data-part="copy"]');
    this.prompt = this.el.querySelector('[data-part="prompt"]');
    this.status = this.el.querySelector('[data-part="status"]');
    this.onCopy = () => this.copy();
    this.button.addEventListener("click", this.onCopy);
    this.button.disabled = false;
  },

  destroyed() {
    this.disposed = true;
    this.button.removeEventListener("click", this.onCopy);
  },

  async copy() {
    if (this.button.disabled) return;
    this.button.disabled = true;
    this.status.textContent = "";

    try {
      await copyTextToClipboard(this.prompt.textContent.trim());
      if (!this.disposed) this.status.textContent = this.el.dataset.successMessage;
    } catch (_error) {
      if (!this.disposed) this.status.textContent = this.el.dataset.errorMessage;
    } finally {
      if (!this.disposed) {
        this.button.disabled = false;
        // The shared clipboard fallback focuses a temporary textarea.
        this.button.focus({ preventScroll: true });
      }
    }
  },
};
