/**
 * NavbarDropdown Hook
 *
 * Manages dropdown menu interactions for desktop navbar with both hover and click support.
 * Provides smooth transitions between open/closed states with direction-aware animations
 * that slide and fade content based on menu position.
 */
export const NavbarDropdown = {
  mounted() {
    const menu = this.el;
    const dropdown = menu.querySelector('[data-part="dropdown"]');
    const action = menu.querySelector('[data-part="action"]');
    let hoverTimeout;
    let isOpen = false;

    if (!dropdown) return;

    // Track currently open dropdown globally
    if (!window.activeNavbarDropdown) {
      window.activeNavbarDropdown = null;
    }

    // Get menu index for direction awareness
    const getMenuIndex = () => {
      const menus = Array.from(
        document.querySelectorAll('#marketing-navbar-menus [data-part="menu"]')
      );
      return menus.indexOf(menu);
    };

    const setOpenState = (state, options = {}) => {
      const { immediate = false, fromMenu = null } = options;

      menu.dataset.open = state ? "true" : "false";
      dropdown.dataset.open = state ? "true" : "false";

      if (action) {
        action.dataset.open = state ? "true" : "false";
        action.setAttribute("aria-expanded", state ? "true" : "false");
      }

      // Handle direction-aware transitions
      if (state && fromMenu) {
        const currentIndex = getMenuIndex();
        const fromIndex = fromMenu.getMenuIndex ? fromMenu.getMenuIndex() : -1;

        if (fromIndex !== -1 && fromIndex !== currentIndex) {
          const direction = currentIndex > fromIndex ? "right" : "left";
          dropdown.dataset.transitionFrom = direction;

          // Remove the attribute after animation completes
          setTimeout(() => {
            dropdown.removeAttribute("data-transition-from");
          }, 300);
        }
      }

      isOpen = state;

      // Update global tracker
      if (state) {
        if (
          window.activeNavbarDropdown &&
          window.activeNavbarDropdown !== menu
        ) {
          // Close previously open dropdown with transition info
          const previousDropdown = window.activeNavbarDropdown.querySelector(
            '[data-part="dropdown"]'
          );
          if (previousDropdown) {
            previousDropdown.dataset.transitionTo =
              getMenuIndex() > window.activeNavbarDropdown.getMenuIndex()
                ? "left"
                : "right";
            setTimeout(() => {
              previousDropdown.removeAttribute("data-transition-to");
            }, 300);
          }
          window.activeNavbarDropdown.setOpenState(false, { immediate: true });
        }
        window.activeNavbarDropdown = menu;
      } else if (window.activeNavbarDropdown === menu) {
        window.activeNavbarDropdown = null;
      }
    };

    // Expose methods for cross-dropdown communication
    menu.setOpenState = setOpenState;
    menu.getMenuIndex = getMenuIndex;

    // Initialize ARIA attributes
    if (action) {
      const dropdownId = dropdown.getAttribute("data-dropdown");
      action.setAttribute("role", "button");
      action.setAttribute("aria-haspopup", "true");
      action.setAttribute(
        "aria-controls",
        `marketing-navbar-${dropdownId}-dropdown`
      );
      action.setAttribute("tabindex", "0");
    }

    if (dropdown) {
      const dropdownId = dropdown.getAttribute("data-dropdown");
      dropdown.setAttribute("id", `marketing-navbar-${dropdownId}-dropdown`);
      dropdown.setAttribute("role", "menu");
    }

    setOpenState(false);

    const showDropdown = () => {
      clearTimeout(hoverTimeout);

      // Calculate dropdown position relative to the menu action button
      const actionRect = action.getBoundingClientRect();
      const dropdownTop = actionRect.bottom - 26;
      dropdown.style.top = `${dropdownTop}px`;

      setOpenState(true, { fromMenu: window.activeNavbarDropdown });
    };

    const hideDropdown = () => {
      clearTimeout(hoverTimeout);
      hoverTimeout = setTimeout(() => {
        setOpenState(false);
      }, 100);
    };

    const toggleDropdown = (e) => {
      e.stopPropagation();
      setOpenState(!isOpen, { fromMenu: window.activeNavbarDropdown });
    };

    // Click to toggle
    if (action) {
      action.addEventListener("click", toggleDropdown);

      // Keyboard support
      action.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          toggleDropdown(e);
        }
      });
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
};
