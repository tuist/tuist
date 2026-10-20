// Scroll-triggered collapse entrance for the "Minimal overhead" card:
// every column starts as a solid full-height cost bar that squashes down
// into its cached box, leaving the dithered ghost behind — the build time
// that didn't happen. The bars/boxes are pure CSS keyframes, staggered per
// column via each column's --delay; this hook arms the pre-state, starts
// the play when the card scrolls into view, and rolls the time values like
// a slot machine while their column animates, settling on the real value
// as it lands — so the times read as measured, not predetermined. (The
// digits can roll in JS because the values are Geist Mono: no layout
// shift.)
//
// Under reduced motion (or without JS) nothing is armed and the card shows
// its final frame with the real values.

const COLUMN_STAGGER = 120;
const COLLAPSE_DURATION = 500;
const BOX_SPIN_DURATION = 300;
const SPIN_TICK = 45;

export const CacheMinimalOverhead = {
  mounted() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    this.timers = [];
    this.el.setAttribute("data-armed", "");

    // Play only once the whole card (the cell: chart + copy) is in view —
    // triggering mid-scroll finishes the entrance before anyone sees it.
    // The threshold backs off for viewports shorter than the card, where
    // full visibility never happens.
    const card = this.el.closest('[data-part="cell"]') || this.el;
    const threshold = card.offsetHeight > window.innerHeight * 0.9 ? 0.5 : 0.9;

    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          this.observer.disconnect();
          this.observer = null;
          this.play();
        }
      },
      { threshold },
    );
    this.observer.observe(card);
  },

  destroyed() {
    if (this.observer) this.observer.disconnect();
    // Timeout and interval ids share a namespace, so clearTimeout clears
    // both kinds.
    if (this.timers) this.timers.forEach((id) => window.clearTimeout(id));
  },

  play() {
    this.el.setAttribute("data-play", "");

    this.el.querySelectorAll('[data-part="column"]').forEach((column, index) => {
      const delay = index * COLUMN_STAGGER;
      // The uncached time rolls while the cost bar collapses and uncovers
      // it; the cached seconds roll while their box pops in.
      this.spin(column.querySelector('[data-part="ghost"] > [data-part="value"]'), delay, COLLAPSE_DURATION);
      this.spin(
        column.querySelector('[data-part="cached"] > [data-part="value"]'),
        delay + COLLAPSE_DURATION,
        BOX_SPIN_DURATION,
      );
    });
  },

  // Rolls every digit of the value randomly (structure — the m/s markers —
  // stays fixed) for `duration` ms, then settles on the real value.
  spin(el, delay, duration) {
    if (!el) return;
    const finalValue = el.textContent.trim();

    this.timers.push(
      window.setTimeout(() => {
        const roll = window.setInterval(() => {
          el.textContent = finalValue.replace(/\d/g, () => Math.floor(Math.random() * 10));
        }, SPIN_TICK);
        this.timers.push(roll);

        this.timers.push(
          window.setTimeout(() => {
            window.clearInterval(roll);
            el.textContent = finalValue;
          }, duration),
        );
      }, delay),
    );
  },
};
