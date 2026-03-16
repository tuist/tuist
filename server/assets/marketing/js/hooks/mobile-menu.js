/**
 * MobileMenu Hook
 *
 * Manages the mobile menu toggle button interaction. Opens and closes the full-screen
 * mobile navigation menu, handles escape key closing, and manages body scroll locking
 * to prevent background scrolling when the menu is open.
 *
 * Preserves open/closed state across LiveView DOM patches so that periodic server
 * updates (e.g. live counters) don't collapse an open menu.
 */
export const MobileMenu = {
  mounted() {
    this.initMenu();
  },

  updated() {
    const wasOpen = this.isOpen || false;
    this.cleanup();
    this.initMenu(wasOpen);
  },

  destroyed() {
    this.cleanup();
  },

  cleanup() {
    if (this.listeners) {
      this.listeners.forEach(({ element, event, handler }) => {
        element.removeEventListener(event, handler);
      });
      this.listeners = [];
    }

    if (this.isOpen) {
      document.body.style.overflow = "";
      this.isOpen = false;
    }
  },

  initMenu(restoreOpen = false) {
    const button = this.el;
    const navbar = document.getElementById("marketing-navbar");
    this.isOpen = false;
    this.listeners = [];

    if (!navbar) {
      console.error("Marketing navbar not found");
      return;
    }

    const addListener = (element, event, handler) => {
      element.addEventListener(event, handler);
      this.listeners.push({ element, event, handler });
    };

    const setOpenState = (state) => {
      this.isOpen = state;
      navbar.dataset.mobileMenuOpen = state ? "true" : "false";
      button.setAttribute("aria-expanded", state ? "true" : "false");
      document.body.style.overflow = state ? "hidden" : "";
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

    button.setAttribute("role", "button");
    button.setAttribute("aria-expanded", "false");
    button.setAttribute("aria-label", "Toggle mobile menu");

    addListener(button, "click", toggleMenu);
    addListener(document, "keydown", handleEscape);

    if (restoreOpen) {
      setOpenState(true);
    }
  },
};
