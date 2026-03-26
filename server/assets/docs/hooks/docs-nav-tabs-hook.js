function syncTabs(el) {
  const activeTab = el.getAttribute("data-active-tab");
  for (const tab of document.querySelectorAll("#docs-nav-tabs .noora-button-group-item")) {
    if (tab.getAttribute("data-tab") === activeTab) tab.setAttribute("data-selected", "");
    else tab.removeAttribute("data-selected");
  }
}

export default {
  mounted() {
    syncTabs(this.el);
  },
  updated() {
    syncTabs(this.el);
  },
};
