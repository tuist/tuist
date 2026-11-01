import { copyTextToClipboard } from "../../shared/js/clipboard.js";

// These are ordinary POST pages, not LiveViews: mount their copy controls
// directly rather than attaching hooks that never join a LiveView socket.
export function initMFA() {
  for (const button of document.querySelectorAll("#mfa [data-mfa-copy]")) {
    button.addEventListener("click", async () => {
      const source = document.querySelector(button.dataset.mfaCopy);
      const status = document.getElementById("mfa-copy-status");
      const text = source.innerText.trim();
      try {
        if (navigator.clipboard?.writeText && window.isSecureContext) {
          await navigator.clipboard.writeText(text).catch(() => copyTextToClipboard(text));
        } else {
          await copyTextToClipboard(text);
        }
        status.textContent = button.dataset.copied;
      } catch {
        status.textContent = button.dataset.copyError;
      }
      button.focus();
    });
  }
}
