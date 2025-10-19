const Hooks = {
  NavbarDropdown: {
    mounted() {
      const menu = this.el;
      const dropdown = menu.querySelector('[data-part="dropdown"]');
      const action = menu.querySelector('[data-part="action"]');
      let hoverTimeout;
      let isOpen = false;

      if (!dropdown) return;

      const setOpenState = (state) => {
        menu.dataset.open = state ? "true" : "false";
        dropdown.dataset.open = state ? "true" : "false";
        if (action) action.dataset.open = state ? "true" : "false";
        isOpen = state;
      };

      setOpenState(false);

      const showDropdown = () => {
        clearTimeout(hoverTimeout);
        setOpenState(true);
      };

      const hideDropdown = () => {
        clearTimeout(hoverTimeout);
        hoverTimeout = setTimeout(() => {
          setOpenState(false);
        }, 100); // Small delay to allow cursor to move to dropdown
      };

      const toggleDropdown = (e) => {
        e.stopPropagation();
        setOpenState(!isOpen);
      };

      // Click to toggle
      if (action) {
        action.addEventListener("click", toggleDropdown);
      }

      // Show on menu hover
      menu.addEventListener("mouseenter", showDropdown);
      menu.addEventListener("mouseleave", hideDropdown);

      // Keep visible when hovering over dropdown
      dropdown.addEventListener("mouseenter", showDropdown);
      dropdown.addEventListener("mouseleave", hideDropdown);

      // Close when clicking outside
      document.addEventListener("click", (e) => {
        if (!menu.contains(e.target) && isOpen) {
          setOpenState(false);
        }
      });
    },
  },

  MobileMenu: {
    mounted() {
      const button = this.el;
      const navbar = document.getElementById("marketing-navbar");
      const menusNav = navbar?.querySelector('[data-part="menus"]');
      const actionsNav = navbar?.querySelector('[data-part="actions"]');

      if (!navbar) {
        console.error("Navbar not found");
        return;
      }

      let isOpen = false;

      const openMenu = () => {
        isOpen = true;
        navbar.setAttribute("data-mobile-menu-open", "true");
        button.setAttribute("aria-expanded", "true");

        if (menusNav) {
          menusNav.setAttribute("aria-hidden", "false");
        }

        // Prevent body scroll
        document.body.style.overflow = "hidden";
      };

      const closeMenu = () => {
        isOpen = false;
        navbar.setAttribute("data-mobile-menu-open", "false");
        button.setAttribute("aria-expanded", "false");

        if (menusNav) {
          menusNav.setAttribute("aria-hidden", "true");
        }

        // Restore body scroll
        document.body.style.overflow = "";
      };

      const toggleMenu = (e) => {
        e.preventDefault();
        e.stopPropagation();

        if (isOpen) {
          closeMenu();
        } else {
          openMenu();
        }
      };

      // Close on Escape key
      const handleEscape = (e) => {
        if (e.key === "Escape" && isOpen) {
          closeMenu();
        }
      };

      // Toggle menu on button click
      button.addEventListener("click", toggleMenu);

      // Handle keyboard navigation
      document.addEventListener("keydown", handleEscape);

      // Initialize ARIA attributes
      button.setAttribute("aria-expanded", "false");
      button.setAttribute("aria-controls", "marketing-navbar-menus");
      navbar.setAttribute("data-mobile-menu-open", "false");

      if (menusNav) {
        menusNav.setAttribute("aria-hidden", "true");
      }

      // Cleanup
      this.destroyed = () => {
        document.body.style.overflow = "";
        document.removeEventListener("keydown", handleEscape);
      };
    },
  },
};

export { Hooks };
