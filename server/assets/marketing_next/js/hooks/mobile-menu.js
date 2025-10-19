/**
 * MobileMenu Hook
 *
 * Manages the mobile menu toggle button interaction. Opens and closes the full-screen
 * mobile navigation menu, handles escape key closing, and manages body scroll locking
 * to prevent background scrolling when the menu is open.
 */
export const MobileMenu = {
  mounted() {
    const button = this.el;
    const navbar = document.getElementById("marketing-navbar");
    const desktopMenus = navbar?.querySelector('nav[data-part="menus"]');
    const mobileMenus = navbar?.querySelector('nav[data-part="mobile-menus"]');

    if (!navbar) {
      console.error("Navbar not found");
      return;
    }

    let isOpen = false;

    const openMenu = () => {
      isOpen = true;
      navbar.setAttribute("data-mobile-menu-open", "true");
      button.setAttribute("aria-expanded", "true");

      if (desktopMenus) {
        desktopMenus.setAttribute("aria-hidden", "true");
      }

      if (mobileMenus) {
        mobileMenus.setAttribute("aria-hidden", "false");
      }

      // Prevent body scroll
      document.body.style.overflow = "hidden";
    };

    const closeMenu = () => {
      isOpen = false;
      navbar.setAttribute("data-mobile-menu-open", "false");
      button.setAttribute("aria-expanded", "false");

      if (desktopMenus) {
        desktopMenus.setAttribute("aria-hidden", "false");
      }

      if (mobileMenus) {
        mobileMenus.setAttribute("aria-hidden", "true");
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
    button.setAttribute("aria-controls", "marketing-navbar-mobile-menus");
    navbar.setAttribute("data-mobile-menu-open", "false");

    if (desktopMenus) {
      desktopMenus.setAttribute("aria-hidden", "false");
    }

    if (mobileMenus) {
      mobileMenus.setAttribute("id", "marketing-navbar-mobile-menus");
      mobileMenus.setAttribute("aria-hidden", "true");
    }

    // Cleanup
    this.destroyed = () => {
      document.body.style.overflow = "";
      document.removeEventListener("keydown", handleEscape);
    };
  },
};
