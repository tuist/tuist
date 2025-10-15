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
};

export { Hooks };
