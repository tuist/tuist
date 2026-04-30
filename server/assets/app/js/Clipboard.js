import { copyTextToClipboard } from "../../shared/js/clipboard.js";

export function setupClipboard() {
  document.addEventListener(
    "click",
    (event) => {
      const trigger =
        event.target instanceof Element ? event.target.closest("[data-clipboard-value]") : null;

      if (!(trigger instanceof HTMLElement)) {
        return;
      }

      const value = trigger.dataset.clipboardValue;
      if (!value) {
        return;
      }

      event.preventDefault();

      copyTextToClipboard(value, {
        container: trigger.closest("[role='dialog']"),
      }).catch((error) => {
        console.warn("Failed to copy text to clipboard", error);
      });
    },
    true
  );
}

export default {};
