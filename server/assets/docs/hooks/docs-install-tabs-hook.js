import { flashCopyCheck } from "../../shared/js/hooks/code-copy.js";

const INSTALL_COMMANDS = {
  mise: "mise install tuist",
  homebrew: "brew install tuist/tuist/tuist",
};

function selectTab(tabs, selectedTab, codeElement) {
  tabs.forEach((tab) => {
    tab.removeAttribute("data-selected");
    tab.setAttribute("aria-selected", "false");
    tab.setAttribute("tabindex", "-1");
  });
  selectedTab.setAttribute("data-selected", "");
  selectedTab.setAttribute("aria-selected", "true");
  selectedTab.setAttribute("tabindex", "0");

  if (codeElement) {
    codeElement.textContent =
      INSTALL_COMMANDS[selectedTab.textContent.trim()] || "";
  }
}

const DocsInstallTabsHook = {
  mounted() {
    const tabs = Array.from(
      this.el.querySelectorAll("[data-part='terminal-tab']"),
    );
    const codeElement = this.el.querySelector(
      "[data-part='terminal-body'] code",
    );
    const copyButton = this.el.querySelector("[data-part='terminal-copy']");

    // Set up ARIA roles
    tabs.forEach((tab, index) => {
      tab.setAttribute("role", "tab");
      tab.setAttribute("tabindex", index === 0 ? "0" : "-1");
      tab.setAttribute(
        "aria-selected",
        tab.hasAttribute("data-selected") ? "true" : "false",
      );

      tab.addEventListener("click", () => {
        selectTab(tabs, tab, codeElement);
      });

      tab.addEventListener("keydown", (e) => {
        let target;
        if (e.key === "ArrowRight") {
          target = tabs[(tabs.indexOf(tab) + 1) % tabs.length];
        } else if (e.key === "ArrowLeft") {
          target = tabs[(tabs.indexOf(tab) - 1 + tabs.length) % tabs.length];
        }
        if (target) {
          e.preventDefault();
          selectTab(tabs, target, codeElement);
          target.focus();
        }
      });
    });

    if (copyButton && codeElement) {
      copyButton.addEventListener("click", () => {
        navigator.clipboard
          .writeText(codeElement.textContent.trim())
          .then(() => flashCopyCheck(copyButton));
      });
    }
  },
};

export default DocsInstallTabsHook;
