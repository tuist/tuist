function openSidebar() {
  document.body.setAttribute("data-sidebar-open", "");
  document.getElementById("docs-sidebar")?.setAttribute("data-mobile-open", "");
}

function closeSidebar() {
  document.body.removeAttribute("data-sidebar-open");
  document.getElementById("docs-sidebar")?.removeAttribute("data-mobile-open");
}

function toggleSidebar() {
  document.body.hasAttribute("data-sidebar-open") ? closeSidebar() : openSidebar();
}

const DocsMobileSidebarHook = {
  mounted() {
    this.el.addEventListener("click", toggleSidebar);

    document
      .querySelector("[data-action='toggle-sidebar']")
      ?.addEventListener("click", toggleSidebar);

    document
      .getElementById("docs-mobile-sidebar-overlay")
      ?.addEventListener("click", closeSidebar);

    document.getElementById("docs-sidebar")?.addEventListener("click", (e) => {
      if (e.target.closest("a[data-part='nav-link'], a[data-part='trigger']")) {
        closeSidebar();
      }
    });
  },
};

export default DocsMobileSidebarHook;
