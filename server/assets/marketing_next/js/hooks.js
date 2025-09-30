const Hooks = {
  NavbarDropdown: {
    mounted() {
      const menu = this.el;
      const dropdown = menu.querySelector('[data-part="dropdown"]');
      const action = menu.querySelector('[data-part="action"]');
      let hoverTimeout;
      let isOpen = false;

      if (!dropdown) return;

      const showDropdown = () => {
        clearTimeout(hoverTimeout);
        dropdown.classList.add("show");
        if (action) action.classList.add("open");
        isOpen = true;
      };

      const hideDropdown = () => {
        clearTimeout(hoverTimeout);
        hoverTimeout = setTimeout(() => {
          dropdown.classList.remove("show");
          if (action) action.classList.remove("open");
          isOpen = false;
        }, 100); // Small delay to allow cursor to move to dropdown
      };

      const toggleDropdown = (e) => {
        e.stopPropagation();
        if (isOpen) {
          dropdown.classList.remove("show");
          if (action) action.classList.remove("open");
          isOpen = false;
        } else {
          dropdown.classList.add("show");
          if (action) action.classList.add("open");
          isOpen = true;
        }
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
          dropdown.classList.remove("show");
          if (action) action.classList.remove("open");
          isOpen = false;
        }
      });
    },
  },
};

export { Hooks };
