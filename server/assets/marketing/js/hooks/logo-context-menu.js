/**
 * LogoContextMenu Hook
 *
 * Right-clicking the navbar logo opens a brand-assets menu instead of the
 * browser context menu (Vercel-style). Left click keeps navigating home.
 * Copy items fetch the light-mode SVG and put its markup on the clipboard,
 * flashing an inline "copied" state without dismissing the menu. The menu
 * only closes on outside click, Escape, resize, link navigation, or when
 * the pointer moves into the navbar's other menus (so it never overlaps
 * the mega-menu panels).
 */
export const LogoContextMenu = {
  mounted() {
    this.listeners = [];

    const brand = this.el;
    const trigger = brand.querySelector('[data-part="tuist"]');
    const menu = brand.querySelector('[data-part="logo-menu"]');

    if (!trigger || !menu) return;

    const addListener = (element, event, handler) => {
      element.addEventListener(event, handler);
      this.listeners.push({ element, event, handler });
    };

    const setOpen = (open) => {
      menu.dataset.open = open ? "true" : "false";
    };

    addListener(trigger, "contextmenu", (event) => {
      event.preventDefault();
      setOpen(menu.dataset.open !== "true");
    });

    // Right-clicks inside the open panel keep the browser's native menu
    // (Inspect Element etc.) — only the logo itself hijacks contextmenu.
    addListener(document, "click", (event) => {
      if (!brand.contains(event.target)) setOpen(false);
    });

    addListener(document, "keydown", (event) => {
      if (event.key === "Escape") setOpen(false);
    });

    addListener(window, "resize", () => setOpen(false));

    // Safe-area behavior mirroring the mega menu: the brand block and the
    // panel below it keep the menu open, but wandering into the rest of the
    // navbar — the menu triggers, the actions cluster, or an opening mega
    // menu panel — dismisses it so the two dropdowns never overlap.
    const navbar = brand.closest("#marketing-navbar");
    if (navbar) {
      const neighbors = [
        navbar.querySelector('[data-part="menus"]'),
        navbar.querySelector('[data-part="actions"]'),
        navbar.querySelector('[data-part="viewport"]'),
      ].filter(Boolean);
      neighbors.forEach((neighbor) => {
        addListener(neighbor, "mouseenter", () => setOpen(false));
      });
    }

    // Copy items flash inline feedback and revert in place: the data-copied
    // flag fades the row's check icon in and out via CSS. Copying never
    // closes the menu — it only dismisses on outside click, Escape, or when
    // the pointer moves to the navbar's other menus.
    // One copied state at a time: starting a copy immediately reverts the
    // other row's feedback, so rapid clicks can't leave two checkmarks up.
    this.copyTimers = new Map();
    const copyItems = Array.from(menu.querySelectorAll("[data-copy-url]"));
    const resetCopied = (item) => {
      clearTimeout(this.copyTimers.get(item));
      this.copyTimers.delete(item);
      delete item.dataset.copied;
    };
    copyItems.forEach((item) => {
      addListener(item, "click", async () => {
        if (item.dataset.copied === "true") return;
        copyItems.filter((other) => other !== item).forEach(resetCopied);
        try {
          const response = await fetch(item.dataset.copyUrl);
          const svg = await response.text();
          await navigator.clipboard.writeText(svg);
        } catch (_error) {
          // Clipboard access denied or asset unreachable — nothing to do.
        }
        item.dataset.copied = "true";
        this.copyTimers.set(
          item,
          setTimeout(() => resetCopied(item), 2000),
        );
      });
    });

    menu.querySelectorAll('a[data-part="item"]').forEach((link) => {
      addListener(link, "click", () => setOpen(false));
    });
  },

  destroyed() {
    if (this.copyTimers) {
      this.copyTimers.forEach((timer) => clearTimeout(timer));
      this.copyTimers.clear();
    }
    if (this.listeners) {
      this.listeners.forEach(({ element, event, handler }) => {
        element.removeEventListener(event, handler);
      });
      this.listeners = [];
    }
  },
};
