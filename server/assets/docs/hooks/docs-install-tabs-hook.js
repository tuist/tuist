import { flashCopyCheck } from "../../shared/js/hooks/code-copy.js";
import { copyTextToClipboard } from "../../shared/js/clipboard.js";

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
    codeElement.textContent = INSTALL_COMMANDS[selectedTab.textContent.trim()] || "";
  }
}

function stopCardNavigation(event) {
  event.preventDefault();
  event.stopPropagation();
}

const DocsInstallTabsHook = {
  mounted() {
    const tabs = Array.from(this.el.querySelectorAll("[data-part='terminal-tab']"));
    const codeElement = this.el.querySelector("[data-part='terminal-body'] code");
    const terminalBody = this.el.querySelector("[data-part='terminal-body']");
    const copyButton = this.el.querySelector("[data-part='terminal-copy']");

    // Set up ARIA roles
    tabs.forEach((tab, index) => {
      tab.setAttribute("role", "tab");
      tab.setAttribute("tabindex", index === 0 ? "0" : "-1");
      tab.setAttribute("aria-selected", tab.hasAttribute("data-selected") ? "true" : "false");

      tab.addEventListener("click", (event) => {
        stopCardNavigation(event);
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
          stopCardNavigation(e);
          selectTab(tabs, target, codeElement);
          target.focus();
        }
      });
    });

    if (terminalBody) {
      ["mousedown", "mouseup", "click"].forEach((eventName) => {
        terminalBody.addEventListener(eventName, stopCardNavigation);
      });
    }

    if (copyButton && codeElement) {
      copyButton.setAttribute("aria-label", "Copy code");

      copyButton.addEventListener("click", (event) => {
        stopCardNavigation(event);
        copyTextToClipboard(codeElement.textContent.trim())
          .then(() => flashCopyCheck(copyButton))
          .catch((err) => console.error("Failed to copy code:", err));
      });

      copyButton.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          stopCardNavigation(event);
          copyButton.click();
        }
      });
    }
  },
};

export default DocsInstallTabsHook;
