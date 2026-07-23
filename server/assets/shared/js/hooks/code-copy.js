import { copyTextToClipboard } from "../clipboard.js";

function flashCopyCheck(button) {
  button.setAttribute("data-copied", "");
  button.setAttribute("aria-label", "Copied");
  setTimeout(() => {
    button.removeAttribute("data-copied");
    button.setAttribute("aria-label", "Copy code");
  }, 2000);
}

function copySourceText(container) {
  return container?.querySelector('[data-part="copy-source"]')?.content?.textContent;
}

function setupCodeCopy(el) {
  el.querySelectorAll('.code-window [data-part="copy"]').forEach((button) => {
    button.setAttribute("role", "button");
    button.setAttribute("tabindex", "0");
    button.setAttribute("aria-label", "Copy code");

    button.addEventListener("click", () => {
      const codeWindow = button.closest(".code-window");
      const codeBlock = codeWindow?.querySelector('[data-part="code"]');
      if (!codeBlock) return;
      copyTextToClipboard(copySourceText(codeWindow) ?? codeBlock.textContent.trim())
        .then(() => flashCopyCheck(button))
        .catch((err) => console.error("Failed to copy code:", err));
    });

    button.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        button.click();
      }
    });
  });
}

const CodeCopy = {
  mounted() {
    setupCodeCopy(this.el);
  },
  updated() {
    setupCodeCopy(this.el);
  },
};

export { CodeCopy, setupCodeCopy, flashCopyCheck, copySourceText };
