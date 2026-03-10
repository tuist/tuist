const INSTALL_COMMANDS = {
  mise: "mise install tuist",
  homebrew: "brew install tuist/tuist/tuist",
};

function selectTab(tabs, selectedTab) {
  tabs.forEach((tab) => tab.removeAttribute("data-selected"));
  selectedTab.setAttribute("data-selected", "");
}

const DocsInstallTabsHook = {
  mounted() {
    const tabs = this.el.querySelectorAll("[data-part='terminal-tab']");
    const codeElement = this.el.querySelector("[data-part='terminal-body'] code");
    const copyButton = this.el.querySelector("[data-part='terminal-copy']");

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        selectTab(tabs, tab);
        if (codeElement) {
          codeElement.textContent = INSTALL_COMMANDS[tab.textContent.trim()] || "";
        }
      });
    });

    if (copyButton && codeElement) {
      copyButton.addEventListener("click", () => {
        navigator.clipboard.writeText(codeElement.textContent.trim());
      });
    }
  },
};

export default DocsInstallTabsHook;
