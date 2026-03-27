import { flashCopyCheck } from "./code-copy.js";

function setupCodeGroups(el) {
  const groups = el.querySelectorAll(".code-group");

  groups.forEach((group) => {
    const tabs = Array.from(group.querySelectorAll('[data-part="tab"]'));
    const panels = group.querySelectorAll('[data-part="panel"]');
    const copyBtn = group.querySelector('[data-part="header"] > [data-part="copy"]');

    function selectTab(tab) {
      const index = tab.getAttribute("data-index");

      tabs.forEach((t) => {
        t.removeAttribute("data-selected");
        t.setAttribute("aria-selected", "false");
        t.setAttribute("tabindex", "-1");
      });
      tab.setAttribute("data-selected", "true");
      tab.setAttribute("aria-selected", "true");
      tab.setAttribute("tabindex", "0");

      panels.forEach((p) => {
        if (p.getAttribute("data-index") === index) {
          p.removeAttribute("data-hidden");
        } else {
          p.setAttribute("data-hidden", "true");
        }
      });
    }

    tabs.forEach((tab, i) => {
      tab.setAttribute("role", "tab");
      tab.setAttribute("tabindex", i === 0 ? "0" : "-1");
      tab.setAttribute("aria-selected", tab.getAttribute("data-selected") === "true" ? "true" : "false");

      tab.addEventListener("click", () => selectTab(tab));

      tab.addEventListener("keydown", (e) => {
        let target;
        if (e.key === "ArrowRight") {
          target = tabs[(tabs.indexOf(tab) + 1) % tabs.length];
        } else if (e.key === "ArrowLeft") {
          target = tabs[(tabs.indexOf(tab) - 1 + tabs.length) % tabs.length];
        }
        if (target) {
          e.preventDefault();
          selectTab(target);
          target.focus();
        }
      });
    });

    if (copyBtn) {
      copyBtn.setAttribute("aria-label", "Copy code");
      copyBtn.setAttribute("role", "button");
      copyBtn.setAttribute("tabindex", "0");

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

      copyBtn.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          copyBtn.click();
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
