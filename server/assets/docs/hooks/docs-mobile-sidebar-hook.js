function updateAriaExpanded(open) {
  document
    .querySelectorAll('[aria-controls="docs-sidebar"]')
    .forEach((el) => el.setAttribute("aria-expanded", String(open)));
}

function openSidebar() {
  document.body.setAttribute("data-sidebar-open", "");
  document.getElementById("docs-sidebar")?.setAttribute("data-mobile-open", "");
  updateAriaExpanded(true);
}

function closeSidebar() {
  document.body.removeAttribute("data-sidebar-open");
  document.getElementById("docs-sidebar")?.removeAttribute("data-mobile-open");
  updateAriaExpanded(false);
}

function toggleSidebar() {
  document.body.hasAttribute("data-sidebar-open") ? closeSidebar() : openSidebar();
}

const DocsMobileSidebarHook = {
  mounted() {
    this.el.addEventListener("click", toggleSidebar);

    document.querySelector("[data-action='toggle-sidebar']")?.addEventListener("click", toggleSidebar);

    document.getElementById("docs-mobile-sidebar-overlay")?.addEventListener("click", closeSidebar);

    document.getElementById("docs-sidebar")?.addEventListener("click", (e) => {
      if (e.target.closest("a[data-part='nav-link'], a[data-part='trigger']")) {
        closeSidebar();
      }
    });

    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && document.body.hasAttribute("data-sidebar-open")) {
        closeSidebar();
        this.el.focus();
      }
    });
  },
};

export default DocsMobileSidebarHook;
