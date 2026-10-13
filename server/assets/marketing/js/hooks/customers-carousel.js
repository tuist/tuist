import { whenInView } from "../lib/in-view.js";

/*
 * Home customers carousel: the previous/next buttons cycle the customer
 * story slides, wrapping at either end, and the carousel advances on its own
 * every AUTOPLAY_MS. The active slide is visible and interactive; the others
 * are inert (hidden from assistive technology and out of the tab order). The
 * card takes the active slide's brand colour through --slide-color, which
 * the stylesheet eases between slides.
 *
 * Autoplay pauses while the pointer is over the carousel or focus is inside
 * it, while it is off screen and while the tab is hidden, and is off under
 * prefers-reduced-motion. Using the buttons restarts the countdown. Only
 * changes the visitor makes are announced: the live region is silenced
 * while autoplay advances.
 *
 * Server-rendered with the first slide active, so without this hook the
 * section still shows one complete story.
 */
const AUTOPLAY_MS = 5000;

export const CustomersCarousel = {
  mounted() {
    this.card = this.el.querySelector('[data-part="card"]');
    this.slides = Array.from(this.el.querySelectorAll('[data-part="slide"]'));
    if (!this.card || this.slides.length === 0) return;
    this.index = Math.max(
      0,
      this.slides.findIndex((slide) => slide.dataset.active === "true"),
    );
    this.cleanups = [];

    this.onClick = (event) => {
      const button = event.target.closest("[data-action]");
      if (!button || !this.el.contains(button)) return;
      const step = button.dataset.action === "previous" ? -1 : button.dataset.action === "next" ? 1 : 0;
      if (step === 0) return;
      this.card.setAttribute("aria-live", "polite");
      this.show(this.index + step);
      this.schedule();
    };
    this.el.addEventListener("click", this.onClick);
    this.cleanups.push(() => this.el.removeEventListener("click", this.onClick));

    if (this.slides.length < 2) {
      for (const button of this.el.querySelectorAll("[data-action]")) button.disabled = true;
      return;
    }

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) return;

    // Autoplay runs only while nothing holds it: hover, focus, off screen or
    // a hidden tab each add a hold.
    this.holds = new Set(["view"]);
    const hold = (reason, on) => {
      if (on) this.holds.add(reason);
      else this.holds.delete(reason);
      this.schedule();
    };
    const listen = (target, type, handler) => {
      target.addEventListener(type, handler);
      this.cleanups.push(() => target.removeEventListener(type, handler));
    };
    listen(this.el, "pointerenter", () => hold("hover", true));
    listen(this.el, "pointerleave", () => hold("hover", false));
    listen(this.el, "focusin", () => hold("focus", true));
    listen(this.el, "focusout", (event) => {
      if (!this.el.contains(event.relatedTarget)) hold("focus", false);
    });
    listen(document, "visibilitychange", () => hold("hidden", document.hidden));
    this.cleanups.push(
      whenInView(this.el, {
        rootMargin: "0px",
        enter: () => hold("view", false),
        leave: () => hold("view", true),
      }),
    );
  },

  destroyed() {
    clearTimeout(this.timer);
    (this.cleanups || []).forEach((fn) => fn());
  },

  // (Re)starts the countdown to the next slide, unless something holds it.
  schedule() {
    clearTimeout(this.timer);
    if (!this.holds || this.holds.size > 0) return;
    this.timer = setTimeout(() => {
      this.card.setAttribute("aria-live", "off");
      this.show(this.index + 1);
      this.schedule();
    }, AUTOPLAY_MS);
  },

  show(index) {
    const count = this.slides.length;
    this.index = ((index % count) + count) % count;
    this.slides.forEach((slide, i) => {
      const active = i === this.index;
      slide.dataset.active = String(active);
      slide.inert = !active;
    });
    const slide = this.slides[this.index];
    this.card.style.setProperty("--slide-color", slide.dataset.color);
    // The dot field morphs into this story's figure.
    this.card
      .querySelector('[data-part="dots"]')
      ?.dispatchEvent(new CustomEvent("customers:figure", { detail: { figure: slide.dataset.figure } }));
  },
};
