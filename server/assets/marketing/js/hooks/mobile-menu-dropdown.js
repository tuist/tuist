/**
 * MobileMenuDropdown Hook
 *
 * Manages collapsible dropdown sections within the mobile menu with smooth animations.
 * Handles click/tap interactions and keyboard accessibility for expanding and collapsing
 * menu sections. Provides smooth height transitions and content fade-in effects.
 * Properly manages ARIA attributes for screen reader accessibility.
 */
export const MobileMenuDropdown = {
  mounted() {
    this.initDropdown();
  },

  updated() {
    this.cleanup();
    this.initDropdown();
  },

  destroyed() {
    this.cleanup();
  },

  cleanup() {
    // Remove all event listeners
    if (this.listeners) {
      this.listeners.forEach(({ element, event, handler }) => {
        element.removeEventListener(event, handler);
      });
      this.listeners = [];
    }

    // Clean up any pending transition listeners
    if (this.dropdown && this.transitionEndHandler) {
      this.dropdown.removeEventListener("transitionend", this.transitionEndHandler);
      this.transitionEndHandler = null;
    }
  },

  initDropdown() {
    const menu = this.el;
    const action = menu.querySelector('[data-part="action"]');
    const dropdown = menu.querySelector('[data-part="dropdown"]');

    if (!action || !dropdown) {
      console.error("Mobile menu dropdown elements not found");
      return;
    }

    this.dropdown = dropdown;
    this.listeners = [];
    let isOpen = false;

    // Helper to add and track event listeners
    const addListener = (element, event, handler) => {
      element.addEventListener(event, handler);
      this.listeners.push({ element, event, handler });
    };

    // Set initial styles for animation
    dropdown.style.height = "0px";
    dropdown.style.overflow = "hidden";
    dropdown.style.transition = "height 0.35s cubic-bezier(0.4, 0, 0.2, 1)";

    const setOpenState = (state) => {
      isOpen = state;
      menu.setAttribute("data-open", state ? "true" : "false");
      action.setAttribute("data-open", state ? "true" : "false");
      action.setAttribute("aria-expanded", state ? "true" : "false");
      dropdown.setAttribute("data-open", state ? "true" : "false");
      dropdown.setAttribute("aria-hidden", state ? "false" : "true");

      if (state) {
        // Opening: calculate target height
        dropdown.style.display = "flex";
        dropdown.style.height = "0px";

        // Get the natural height
        const scrollHeight = dropdown.scrollHeight;

        // Trigger reflow
        dropdown.offsetHeight;

        // Animate to target height
        requestAnimationFrame(() => {
          dropdown.style.height = `${scrollHeight}px`;
        });

        // After animation, set to auto for dynamic content
        this.transitionEndHandler = () => {
          if (isOpen) {
            dropdown.style.height = "auto";
            dropdown.style.overflow = "visible";
          }
          dropdown.removeEventListener("transitionend", this.transitionEndHandler);
          this.transitionEndHandler = null;
        };
        dropdown.addEventListener("transitionend", this.transitionEndHandler, {
          once: true,
        });
      } else {
        // Closing: animate from current height to 0
        dropdown.style.overflow = "hidden";
        const currentHeight = dropdown.scrollHeight;
        dropdown.style.height = `${currentHeight}px`;

        // Trigger reflow
        dropdown.offsetHeight;

        // Animate to 0
        requestAnimationFrame(() => {
          dropdown.style.height = "0px";
        });

        // After animation, hide completely
        this.transitionEndHandler = () => {
          if (!isOpen) {
            dropdown.style.display = "none";
          }
          dropdown.removeEventListener("transitionend", this.transitionEndHandler);
          this.transitionEndHandler = null;
        };
        dropdown.addEventListener("transitionend", this.transitionEndHandler, {
          once: true,
        });
      }
    };

    const toggleDropdown = (e) => {
      e.preventDefault();
      e.stopPropagation();
      setOpenState(!isOpen);
    };

    const keydownHandler = (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        toggleDropdown(e);
      }
    };

    // Make action clickable
    addListener(action, "click", toggleDropdown);
    action.style.cursor = "pointer";

    // Initialize ARIA attributes
    const dropdownId = `mobile-dropdown-${Math.random().toString(36).substr(2, 9)}`;
    dropdown.setAttribute("id", dropdownId);
    action.setAttribute("aria-controls", dropdownId);
    action.setAttribute("role", "button");
    action.setAttribute("tabindex", "0");

    // Handle keyboard interaction
    addListener(action, "keydown", keydownHandler);

    // Initialize closed state
    setOpenState(false);
  },
};

/**
 * MobileMenu Hook
 *
 * Manages the main mobile menu open/close state with smooth animations.
 * Prevents body scroll when menu is open and handles escape key to close.
 */
export const MobileMenu = {
  mounted() {
    this.initMenu();
  },

  updated() {
    this.cleanup();
    this.initMenu();
  },

  destroyed() {
    this.cleanup();
  },

  cleanup() {
    // Remove all event listeners
    if (this.listeners) {
      this.listeners.forEach(({ element, event, handler }) => {
        element.removeEventListener(event, handler);
      });
      this.listeners = [];
    }

    // Restore body scroll if menu was open
    if (this.isOpen) {
      document.body.style.overflow = "";
      this.isOpen = false;
    }
  },

  initMenu() {
    const button = this.el;
    const navbar = document.getElementById("marketing-navbar");
    this.isOpen = false;
    this.listeners = [];

    if (!navbar) {
      console.error("Marketing navbar not found");
      return;
    }

    // Helper to add and track event listeners
    const addListener = (element, event, handler) => {
      element.addEventListener(event, handler);
      this.listeners.push({ element, event, handler });
    };

    const setOpenState = (state) => {
      this.isOpen = state;
      navbar.dataset.mobileMenuOpen = state ? "true" : "false";
      button.setAttribute("aria-expanded", state ? "true" : "false");

      // Prevent body scroll when menu is open
      if (state) {
        document.body.style.overflow = "hidden";
      } else {
        document.body.style.overflow = "";
      }
    };

    const toggleMenu = (e) => {
      e.preventDefault();
      e.stopPropagation();
      setOpenState(!this.isOpen);
    };

    const handleEscape = (e) => {
      if (e.key === "Escape" && this.isOpen) {
        setOpenState(false);
      }
    };

    // Initialize ARIA attributes
    button.setAttribute("role", "button");
    button.setAttribute("aria-expanded", "false");
    button.setAttribute("aria-label", "Toggle mobile menu");

    // Event listeners
    addListener(button, "click", toggleMenu);
    addListener(document, "keydown", handleEscape);
  },
};
