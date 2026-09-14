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
import { closeOnNavigation } from "../lib/close-on-navigation.js";

export const MobileMenu = {
  mounted() {
    this.initMenu();
  },

  updated() {
    this.updateMenu();
  },

  destroyed() {
    this.cleanup();
  },

  cleanup() {
    if (this.stopClosingOnNavigation) {
      this.stopClosingOnNavigation();
      this.stopClosingOnNavigation = null;
    }

    if (this.listeners) {
      this.listeners.forEach(({ element, event, handler }) => {
        element.removeEventListener(event, handler);
      });
      this.listeners = [];
    }

    if (this.isOpen) {
      document.documentElement.style.overflow = "";
      document.body.style.touchAction = "";
      this.isOpen = false;
    }
  },

  updateMenu() {
    const navbar = document.getElementById("marketing-navbar");
    if (!navbar) return;

    const isOpen = this.isOpen || false;
    navbar.dataset.mobileMenuOpen = isOpen ? "true" : "false";
    this.el.setAttribute("aria-expanded", isOpen ? "true" : "false");
    // Drives the CSS hamburger <-> X animation (navbar.css).
    this.el.dataset.state = isOpen ? "open" : "closed";
    document.documentElement.style.overflow = isOpen ? "hidden" : "";
    document.body.style.touchAction = isOpen ? "none" : "";
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

    const addListener = (element, event, handler) => {
      element.addEventListener(event, handler);
      this.listeners.push({ element, event, handler });
    };

    // Prefetch the menu's own pages the first time it opens, through a
    // speculation rule inserted at runtime, so a tap lands on a page that is
    // already fetched. Desktop gets the same from the layout's hover rule;
    // phones have no hover, so without this every tap starts from zero.
    // Same-origin, same-tab links only; skipped under Save-Data. Browsers
    // without speculation rules (Safari) ignore the script.
    const prefetchMenuLinks = () => {
      if (this.prefetched) return;
      this.prefetched = true;
      if (!HTMLScriptElement.supports || !HTMLScriptElement.supports("speculationrules")) return;
      if (navigator.connection && navigator.connection.saveData) return;
      const urls = new Set();
      for (const link of navbar.querySelectorAll('[data-part="mobile-menus"] a[href]')) {
        if (link.origin !== location.origin) continue;
        if (link.target && link.target !== "_self") continue;
        if (link.hasAttribute("download")) continue;
        if (link.pathname === location.pathname) continue;
        urls.add(link.pathname + link.search);
      }
      if (!urls.size) return;
      const script = document.createElement("script");
      script.type = "speculationrules";
      const nonce = document.querySelector("meta[name='csp-nonce']");
      if (nonce) script.nonce = nonce.getAttribute("content");
      script.textContent = JSON.stringify({ prefetch: [{ urls: [...urls] }] });
      document.head.appendChild(script);
    };

    const setOpenState = (state) => {
      this.isOpen = state;
      if (state) prefetchMenuLinks();
      // The panel is a fixed overlay that starts under the bar (navbar.css).
      if (state) {
        navbar.style.setProperty("--marketing-navbar-height", `${navbar.offsetHeight}px`);
        // The panel stays in the tree while closed (so closing animates),
        // which also keeps its scroll offset; reopen from the top.
        const panel = navbar.querySelector('[data-part="mobile-menus"]');
        if (panel) panel.scrollTop = 0;
      }
      navbar.dataset.mobileMenuOpen = state ? "true" : "false";
      button.setAttribute("aria-expanded", state ? "true" : "false");
      // Drives the CSS hamburger <-> X animation (navbar.css).
      button.dataset.state = state ? "open" : "closed";
      lockScroll(state);
    };

    // Scroll lock. overflow: hidden goes on <html>, never on <body>: the
    // stylesheet gives <html> overflow-x: clip, so a body value no longer
    // propagates to the viewport — it would make <body> its own scroll
    // container and the sticky navbar would scroll away with the page. iOS
    // Safari keeps touch-scrolling the document through overflow: hidden
    // anyway, so touch-action: none on the body stops document panning;
    // touches inside the panel are governed by the panel itself (its own
    // scroll container), so it still scrolls, and its overscroll-behavior
    // keeps that from chaining out.
    const lockScroll = (locked) => {
      document.documentElement.style.overflow = locked ? "hidden" : "";
      document.body.style.touchAction = locked ? "none" : "";
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

    // Following any link in the navbar closes the menu (and releases the
    // scroll lock) before the page changes.
    this.stopClosingOnNavigation = closeOnNavigation(navbar, () => {
      if (this.isOpen) setOpenState(false);
    });

    // Force-close when the viewport grows past the mobile breakpoint (e.g.
    // leaving responsive mode in devtools), so the open state and the body
    // scroll lock never leak into the desktop layout.
    const desktopQuery = window.matchMedia("(min-width: 961px)");
    const handleViewportChange = () => {
      if (desktopQuery.matches && this.isOpen) {
        setOpenState(false);
      }
    };
    addListener(desktopQuery, "change", handleViewportChange);
  },
};
