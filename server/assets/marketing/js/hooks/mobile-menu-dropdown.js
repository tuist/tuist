/**
 * MobileMenuDropdown Hook
 *
 * Manages collapsible dropdown sections within the mobile menu. Handles click/tap
 * interactions and keyboard accessibility for expanding and collapsing menu sections.
 * Properly manages ARIA attributes for screen reader accessibility.
 */
export const MobileMenuDropdown = {
  mounted() {
    const menu = this.el;
    const action = menu.querySelector('[data-part="action"]');
    const dropdown = menu.querySelector('[data-part="dropdown"]');

    if (!action || !dropdown) {
      console.error("Mobile menu dropdown elements not found");
      return;
    }

    let isOpen = false;

    const setOpenState = (state) => {
      isOpen = state;
      menu.setAttribute("data-open", state ? "true" : "false");
      action.setAttribute("data-open", state ? "true" : "false");
      action.setAttribute("aria-expanded", state ? "true" : "false");
      dropdown.setAttribute("data-open", state ? "true" : "false");
      dropdown.setAttribute("aria-hidden", state ? "false" : "true");
    };

    const toggleDropdown = (e) => {
      e.preventDefault();
      e.stopPropagation();
      setOpenState(!isOpen);
    };

    // Make action clickable
    action.addEventListener("click", toggleDropdown);
    action.style.cursor = "pointer";

    // Initialize ARIA attributes
    const dropdownId = `mobile-dropdown-${Math.random().toString(36).substr(2, 9)}`;
    dropdown.setAttribute("id", dropdownId);
    action.setAttribute("aria-controls", dropdownId);
    action.setAttribute("role", "button");
    action.setAttribute("tabindex", "0");

    // Handle keyboard interaction
    action.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        toggleDropdown(e);
      }
    });

    // Initialize closed state
    setOpenState(false);
  },
};
