import { flashCopyCheck } from "./code-copy.js";

function setupCodeGroups(el) {
  const groups = el.querySelectorAll(".code-group");

  groups.forEach((group) => {
    const tabs = group.querySelectorAll('[data-part="tab"]');
    const panels = group.querySelectorAll('[data-part="panel"]');
    const copyBtn = group.querySelector('[data-part="header"] > [data-part="copy"]');

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        const index = tab.getAttribute("data-index");

        tabs.forEach((t) => t.removeAttribute("data-selected"));
        tab.setAttribute("data-selected", "true");

        panels.forEach((p) => {
          if (p.getAttribute("data-index") === index) {
            p.removeAttribute("data-hidden");
          } else {
            p.setAttribute("data-hidden", "true");
          }
        });
      });
    });

    if (copyBtn) {
      copyBtn.addEventListener("click", () => {
        const activePanel = group.querySelector('[data-part="panel"]:not([data-hidden="true"])');
        if (activePanel) {
          const codeBlock = activePanel.querySelector('[data-part="code"]');
          if (codeBlock) {
            navigator.clipboard
              .writeText(codeBlock.textContent.trim())
              .then(() => flashCopyCheck(copyBtn))
              .catch((err) => console.error("Failed to copy code:", err));
          }
        }
      });
    }
  });
}

const CodeGroup = {
  mounted() {
    setupCodeGroups(this.el);
  },
  updated() {
    setupCodeGroups(this.el);
  },
};

export { CodeGroup, setupCodeGroups };
