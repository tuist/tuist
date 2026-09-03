/*
 * Shared navbar dropdown, modeled on Radix's NavigationMenu: one viewport
 * stays in place under the bar while content groups animate in/out with
 * direction-aware motion.
 *
 * Contract (consumed by navbar.css):
 *   viewport  [data-open]   — panel visibility (fade/translate transition)
 *   content   [data-state]  — "open" | "closed"
 *   content   [data-motion] — from-start | from-end | to-start | to-end,
 *               set only when switching between two open menus; the values
 *               drive Emil's enter/exit keyframes.
 *   trigger   [data-open] + aria-expanded — active trigger (chevron flip).
 */
export const NavbarMegaMenu = {
  mounted() {
    this.navbar = this.el.closest("#marketing-navbar") || document.getElementById("marketing-navbar");
    this.triggers = [...this.navbar.querySelectorAll("[data-nav-trigger]")];
    this.order = this.triggers.map((t) => t.dataset.navTrigger);
    this.contents = new Map(
      [...this.el.querySelectorAll(':scope > [data-part="panel"] > [data-part="content"]')].map((el) => [
        el.dataset.dropdown,
        el,
      ]),
    );
    this.active = null;
    // A click-opened panel is pinned: hover-out reasons can't close it (so
    // it survives the pointer leaving, e.g. into devtools); only Escape,
    // outside click, or clicking the pinning trigger again dismisses it.
    // Stored by trigger name — hover may switch the active panel between
    // the pinning click and the next one, and clicking a *different*
    // trigger should switch, not close.
    this.pinnedName = null;
    this.cleanups = [];

    const on = (el, event, fn) => {
      el.addEventListener(event, fn);
      this.cleanups.push(() => el.removeEventListener(event, fn));
    };

    for (const trigger of this.triggers) {
      const name = trigger.dataset.navTrigger;
      on(trigger, "mouseenter", () => this.open(name));
      // Tap/click pins, for touch devices and as a hover fallback. Not a
      // blind toggle: mouseenter fires right before click (also on emulated
      // taps), so "active" alone means hover-opened — clicking that pins it
      // rather than closing it again.
      on(trigger, "click", () => {
        if (this.pinnedName === name) {
          this.close("trigger-click");
        } else {
          this.open(name);
          this.pinnedName = name;
        }
      });
    }

    // Hovering a plain menu link (Pricing, Blog), the logo, or the actions
    // cluster closes the panel — those signal the user has left the menu.
    const closers = [
      ...this.navbar.querySelectorAll('[data-part="menus"] [data-part="action"]:not([data-nav-trigger])'),
      this.navbar.querySelector('[data-part="bar"] [data-part="tuist"]'),
      this.navbar.querySelector('[data-part="bar"] > [data-part="actions"]'),
    ].filter(Boolean);
    for (const closer of closers) {
      on(closer, "mouseenter", () => this.close("bar-neutral-hover"));
    }

    // The viewport is a child of the navbar, so one mouseleave covers both
    // the bar and the open panel. Close after a short grace period instead
    // of immediately: crossing the 2px seam between the bar and the panel
    // (or briefly overshooting an edge) shouldn't dismiss the menu.
    this.closeTimer = null;
    on(this.navbar, "mouseleave", () => this.scheduleClose());
    on(this.navbar, "mouseenter", () => this.cancelScheduledClose());

    // Inside the navbar, only the safe path keeps the menu open: the
    // triggers, the panel + halo, and the trapezoid between the active
    // trigger and the panel. Idling on blank bar space closes it.
    on(this.navbar, "mousemove", (e) => {
      if (this.el.dataset.open !== "true") return;
      if (this.isPointerSafe(e.clientX, e.clientY)) {
        this.cancelScheduledClose();
      } else {
        this.scheduleClose();
      }
    });
    on(document, "keydown", (e) => {
      if (e.key === "Escape") this.close("escape");
    });
    on(document, "click", (e) => {
      if (!this.navbar.contains(e.target)) this.close("outside-click");
    });
  },

  destroyed() {
    clearTimeout(this.closeTimer);
    this.cleanups.forEach((fn) => fn());
  },

  scheduleClose() {
    if (this.closeTimer) return;
    this.closeTimer = setTimeout(() => {
      this.closeTimer = null;
      this.close("grace-timer");
    }, 150);
  },

  cancelScheduledClose() {
    clearTimeout(this.closeTimer);
    this.closeTimer = null;
  },

  // True while the pointer is on the forgiving path between the triggers
  // and the panel: any trigger, the viewport (panel + halo), or the
  // trapezoid connecting the active trigger to the panel's top corners.
  isPointerSafe(x, y) {
    const within = (r) => x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;

    if (this.triggers.some((t) => within(t.getBoundingClientRect()))) return true;
    if (within(this.el.getBoundingClientRect())) return true;

    const trigger = this.triggers.find((t) => t.dataset.navTrigger === this.active);
    const panel = this.el.querySelector('[data-part="panel"]');
    if (trigger && panel) {
      const t = trigger.getBoundingClientRect();
      const p = panel.getBoundingClientRect();
      if (p.top > t.bottom && y >= t.bottom && y <= p.top) {
        const f = (y - t.bottom) / (p.top - t.bottom);
        const xLeft = t.left + (p.left - t.left) * f;
        const xRight = t.right + (p.right - t.right) * f;
        if (x >= xLeft && x <= xRight) return true;
      }
    }
    return false;
  },

  open(name) {
    this.cancelScheduledClose();
    const next = this.contents.get(name);
    if (!next || this.active === name) return;

    const prev = this.active;
    const wasOpen = this.el.dataset.open === "true";
    this.active = name;
    this.el.dataset.open = "true";

    if (wasOpen && prev) {
      // Direction-aware handoff between two menus.
      const forward = this.order.indexOf(name) > this.order.indexOf(prev);
      const prevEl = this.contents.get(prev);
      prevEl.dataset.state = "closed";
      prevEl.dataset.motion = forward ? "to-start" : "to-end";
      next.dataset.motion = forward ? "from-end" : "from-start";
    } else {
      // First open: the viewport itself animates in; content just shows.
      delete next.dataset.motion;
    }
    next.dataset.state = "open";
    this.shuffleHighlights(next);

    for (const trigger of this.triggers) {
      const isActive = trigger.dataset.navTrigger === name;
      trigger.dataset.open = String(isActive);
      trigger.setAttribute("aria-expanded", String(isActive));
    }
  },

  // Each open deals a fresh hand of hover-highlighted cells in the panel's
  // illustrations: the SVGs mark every candidate (data-chip / data-square),
  // and the CSS lights whichever ones currently carry the highlight
  // data-part. Both the count and the selection are re-rolled per open.
  shuffleHighlights(content) {
    const groups = [
      { selector: "[data-chip]", marker: "chip-highlight", min: 7, max: 15 },
      { selector: "[data-square]", marker: "square-highlight", min: 45, max: 85 },
    ];
    for (const { selector, marker, min, max } of groups) {
      // Group by owning svg so each illustration rolls its own hand.
      const bySvg = new Map();
      for (const el of content.querySelectorAll(selector)) {
        const svg = el.closest("svg");
        if (!bySvg.has(svg)) bySvg.set(svg, []);
        bySvg.get(svg).push(el);
      }
      for (const cells of bySvg.values()) {
        const count = Math.min(cells.length, min + Math.floor(Math.random() * (max - min + 1)));
        const pool = [...cells];
        for (let i = pool.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          [pool[i], pool[j]] = [pool[j], pool[i]];
        }
        const chosen = new Set(pool.slice(0, count));
        for (const el of cells) {
          if (chosen.has(el)) {
            el.setAttribute("data-part", marker);
          } else if (el.getAttribute("data-part") === marker) {
            el.removeAttribute("data-part");
          }
        }
      }
    }
  },

  close(reason) {
    // Hover-out reasons never dismiss a pinned panel.
    if (this.pinnedName && (reason === "grace-timer" || reason === "bar-neutral-hover")) return;
    if (this.el.dataset.open !== "true") return;
    this.pinnedName = null;
    this.el.dataset.open = "false";
    const activeEl = this.contents.get(this.active);
    if (activeEl) {
      activeEl.dataset.state = "closed";
      delete activeEl.dataset.motion;
    }
    this.active = null;
    for (const trigger of this.triggers) {
      trigger.dataset.open = "false";
      trigger.setAttribute("aria-expanded", "false");
    }
  },
};
