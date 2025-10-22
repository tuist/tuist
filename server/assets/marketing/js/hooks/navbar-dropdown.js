/**
 * NavbarDropdown Hook
 *
 * Manages dropdown menu interactions for desktop navbar with both hover and click support.
 * Provides smooth transitions between open/closed states with a small delay to prevent
 * accidental closures when moving the cursor to the dropdown.
 */
export const NavbarDropdown = {
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
      if (action) {
        action.dataset.open = state ? "true" : "false";
        action.setAttribute("aria-expanded", state ? "true" : "false");
      }
      isOpen = state;
    };

    // Initialize ARIA attributes
    if (action) {
      const dropdownId = dropdown.getAttribute("data-dropdown");
      action.setAttribute("role", "button");
      action.setAttribute("aria-haspopup", "true");
      action.setAttribute("aria-controls", `marketing-navbar-${dropdownId}-dropdown`);
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
      const dropdownTop = actionRect.bottom - 26; // 20px spacing
      dropdown.style.top = `${dropdownTop}px`;

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
