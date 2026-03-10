function updateSidebarSelection(currentSlug) {
  const sidebar = document.getElementById("docs-sidebar");
  if (!sidebar) return;

  sidebar.querySelectorAll("a[data-part='nav-link'], a[data-part='trigger']").forEach((link) => {
    const tabMenu = link.querySelector(".noora-tab-menu-vertical");
    if (!tabMenu) return;

    const isActive = link.getAttribute("href") === "/docs" + currentSlug;
    if (isActive) {
      tabMenu.setAttribute("data-selected", "true");
    } else {
      tabMenu.removeAttribute("data-selected");
    }
  });

  sidebar.querySelectorAll(".noora-tab-menu-vertical[data-part='trigger']").forEach((el) => {
    el.removeAttribute("data-selected");
  });
}

function updateNavTabSelection(activeTab) {
  const navTabs = document.getElementById("docs-nav-tabs");
  if (!navTabs) return;

  navTabs.querySelectorAll(".noora-button-group-item").forEach((tab) => {
    if (tab.dataset.tab === activeTab) {
      tab.setAttribute("data-selected", "");
    } else {
      tab.removeAttribute("data-selected");
    }
  });
}

function syncPageState(el) {
  updateSidebarSelection(el.dataset.currentSlug);
  updateNavTabSelection(el.dataset.currentTab);
}

const DocsActivePageHook = {
  mounted() {
    syncPageState(this.el);
  },
  updated() {
    syncPageState(this.el);
    window.scrollTo(0, 0);
  },
};

export default DocsActivePageHook;
