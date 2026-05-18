import { copyTextToClipboard } from "../clipboard.js";

function flashCopyCheck(button) {
  button.setAttribute("data-copied", "");
  button.setAttribute("aria-label", "Copied");
  setTimeout(() => {
    button.removeAttribute("data-copied");
    button.setAttribute("aria-label", "Copy code");
  }, 2000);
}

function setupCodeCopy(el) {
  el.querySelectorAll('.code-window [data-part="copy"]').forEach((button) => {
    button.setAttribute("role", "button");
    button.setAttribute("tabindex", "0");
    button.setAttribute("aria-label", "Copy code");

    button.addEventListener("click", () => {
      const codeBlock = button.closest(".code-window")?.querySelector('[data-part="code"]');
      if (!codeBlock) return;
      copyTextToClipboard(codeBlock.textContent.trim())
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

export { CodeCopy, setupCodeCopy, flashCopyCheck };
