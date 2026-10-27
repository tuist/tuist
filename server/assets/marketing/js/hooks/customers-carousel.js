/*
 * Home customers carousel: a row of customer logo tabs selects the story
 * shown in the card below, and the carousel advances on its own every
 * AUTOPLAY_MS, wrapping after the last story. It follows the tabs pattern:
 * the selected tab is the only one in the tab order (arrow keys, Home and
 * End move between tabs and select as they go), and the active panel is the
 * only one visible and interactive; the others are inert. The card's dot
 * field takes the active story's colour through --slide-color. A single
 * underline slides to the selected tab, placed from its measured box; it
 * jumps without animating on load and resize. On phones the tab row is a
 * single sideways-scrolling strip: its edges fade while there's more in
 * that direction, and a newly selected tab is scrolled into view.
 *
 * Autoplay starts on page load (the first story, OpenAI, shows first) and
 * cycles continuously, on screen or off. It pauses while a mouse pointer is
 * over the carousel (touch taps don't pause it), while keyboard focus is
 * inside it (a mouse click on a tab doesn't count, so it never sticks paused
 * after a click) and while the browser tab is hidden, and is off under
 * prefers-reduced-motion. Choosing a tab restarts the countdown. Only
 * changes the visitor makes are announced: the live region is silenced
 * while autoplay advances.
 *
 * Server-rendered with the first story selected, so without this hook the
 * section still shows one complete story.
 */
const AUTOPLAY_MS = 5000;

export const CustomersCarousel = {
  mounted() {
    this.card = this.el.querySelector('[data-part="card"]');
    this.slides = Array.from(this.el.querySelectorAll('[data-part="slide"]'));
    this.tabs = Array.from(this.el.querySelectorAll('[data-part="tab"]'));
    this.tablist = this.el.querySelector('[data-part="tabs"]');
    this.indicator = this.el.querySelector('[data-part="indicator"]');
    if (!this.card || this.slides.length === 0) return;
    this.index = Math.max(
      0,
      this.slides.findIndex((slide) => slide.dataset.active === "true"),
    );
    this.cleanups = [];
    const listen = (target, type, handler) => {
      target.addEventListener(type, handler);
      this.cleanups.push(() => target.removeEventListener(type, handler));
    };

    if (this.tablist && this.indicator) {
      this.placeIndicator({ animate: false });
      this.tablist.dataset.indicator = "";
    }
    if (this.tablist) {
      this.updateFades();
      listen(this.tablist, "scroll", () => this.updateFades());
      const observer = new ResizeObserver(() => {
        this.placeIndicator({ animate: false });
        this.updateFades();
      });
      observer.observe(this.tablist);
      this.cleanups.push(() => observer.disconnect());
    }

    // A visitor's choice: announce it and restart the autoplay countdown.
    const choose = (index, { focus = false } = {}) => {
      this.card.setAttribute("aria-live", "polite");
      this.show(index);
      if (focus) this.tabs[this.index]?.focus();
      this.schedule();
    };
    listen(this.el, "click", (event) => {
      const tab = event.target.closest('[data-part="tab"]');
      if (tab && this.el.contains(tab)) choose(Number(tab.dataset.index));
    });
    listen(this.el, "keydown", (event) => {
      if (!event.target.closest('[data-part="tab"]')) return;
      const target = {
        ArrowRight: this.index + 1,
        ArrowLeft: this.index - 1,
        Home: 0,
        End: this.tabs.length - 1,
      }[event.key];
      if (target === undefined) return;
      event.preventDefault();
      choose(target, { focus: true });
    });

    if (this.slides.length < 2) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) return;

    // Autoplay runs unless something holds it: a hovering mouse, keyboard
    // focus inside the carousel, or a hidden browser tab.
    this.holds = new Set(document.hidden ? ["hidden"] : []);
    const hold = (reason, on) => {
      if (on) this.holds.add(reason);
      else this.holds.delete(reason);
      this.schedule();
    };
    listen(this.el, "pointerenter", (event) => {
      if (event.pointerType === "mouse") hold("hover", true);
    });
    listen(this.el, "pointerleave", () => hold("hover", false));
    // Keyboard focus only: buttons match :focus-visible when reached with
    // the keyboard, not when clicked with a mouse.
    listen(this.el, "focusin", (event) => {
      if (event.target.matches?.(":focus-visible")) hold("focus", true);
    });
    listen(this.el, "focusout", (event) => {
      if (!this.el.contains(event.relatedTarget)) hold("focus", false);
    });
    listen(document, "visibilitychange", () => hold("hidden", document.hidden));
    this.schedule();
  },

  destroyed() {
    clearTimeout(this.timer);
    (this.cleanups || []).forEach((fn) => fn());
  },

  // (Re)starts the countdown to the next story, unless something holds it.
  schedule() {
    clearTimeout(this.timer);
    if (!this.holds || this.holds.size > 0) return;
    this.timer = setTimeout(() => {
      this.card.setAttribute("aria-live", "off");
      this.show(this.index + 1);
      this.schedule();
    }, AUTOPLAY_MS);
  },

  // Moves the underline to the selected tab. Positions are the tab's box
  // within the tab row, which is the indicator's containing block.
  placeIndicator({ animate = true } = {}) {
    const tab = this.tabs[this.index];
    if (!this.indicator || !tab) return;
    if (!animate) this.indicator.dataset.instant = "";
    this.indicator.style.setProperty("--indicator-x", `${tab.offsetLeft}px`);
    this.indicator.style.setProperty("--indicator-y", `${tab.offsetTop + tab.offsetHeight - 2}px`);
    this.indicator.style.setProperty("--indicator-w", `${tab.offsetWidth}px`);
    if (!animate) {
      this.indicator.getBoundingClientRect();
      delete this.indicator.dataset.instant;
    }
  },

  // Fades the tab row's edges while it can scroll further that way (only
  // the phone layout ever overflows).
  updateFades() {
    const row = this.tablist;
    if (!row) return;
    const more = row.scrollWidth - row.clientWidth;
    row.style.setProperty("--fade-start", row.scrollLeft > 1 ? "40px" : "0px");
    row.style.setProperty("--fade-end", row.scrollLeft < more - 1 ? "40px" : "0px");
  },

  // Scrolls the tab row, never the page, to centre the selected tab.
  revealTab() {
    const row = this.tablist;
    const tab = this.tabs[this.index];
    if (!row || !tab || row.scrollWidth <= row.clientWidth) return;
    const left = tab.offsetLeft - (row.clientWidth - tab.offsetWidth) / 2;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    row.scrollTo({ left: Math.max(0, left), behavior: reduced ? "auto" : "smooth" });
  },

  show(index) {
    const count = this.slides.length;
    this.index = ((index % count) + count) % count;
    this.slides.forEach((slide, i) => {
      const active = i === this.index;
      slide.dataset.active = String(active);
      slide.inert = !active;
    });
    this.tabs.forEach((tab, i) => {
      const selected = i === this.index;
      tab.setAttribute("aria-selected", String(selected));
      tab.tabIndex = selected ? 0 : -1;
    });
    this.placeIndicator();
    this.revealTab();
    const slide = this.slides[this.index];
    this.card.style.setProperty("--slide-color", slide.dataset.color);
    // The dot field morphs into this story's figure.
    this.card
      .querySelector('[data-part="dots"]')
      ?.dispatchEvent(new CustomEvent("customers:figure", { detail: { figure: slide.dataset.figure } }));
  },
};
