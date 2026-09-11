// Typewriter entrance for the compute hero's migration diff: the added
// line's code types out once per page load behind a terminal-style block
// cursor that stays solid while typing and blinks continuously once the
// line has landed. The GitHub/Buildkite switch above the diff sets
// data-ci on it, which picks the variant the stylesheet shows; switching
// shows the other variant's final frame at once, no retyping. An inline
// first-paint script in the template arms the diff (stashing every added
// line into data-text and clearing it) before the browser paints, so the
// full text never flashes ahead of the typing; without JS, or under
// reduced motion, the diff just shows its final frame with no cursor.

const START_DELAY = 600;
const MIN_TICK = 45;
const MAX_TICK = 110;

export const ComputeHeroDiff = {
  mounted() {
    this.diff = this.el.querySelector('[data-part="diff"]');
    if (!this.diff) return;

    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.timers = [];
    // Tells the inline watchdog the hook owns the diff from here on.
    this.diff.setAttribute("data-hooked", "");

    const typedSpans = this.diff.querySelectorAll('[data-part="typed"]');

    if (this.reducedMotion) {
      // The inline script skips arming under reduced motion too; restoring
      // here just covers the two checks ever disagreeing.
      if (this.diff.hasAttribute("data-armed")) {
        typedSpans.forEach((span) => (span.textContent = span.dataset.text || span.textContent));
        this.diff.removeAttribute("data-armed");
      }
    } else {
      // The inline script normally arms before first paint; arming here is
      // the fallback for when it was blocked.
      if (!this.diff.hasAttribute("data-armed")) {
        typedSpans.forEach((span) => {
          span.dataset.text = span.textContent;
          span.textContent = "";
        });
        this.diff.setAttribute("data-armed", "");
      }
      this.type(START_DELAY);
    }

    this.buttons = Array.from(this.el.querySelectorAll('[data-part="ci-switch"] [data-ci]'));
    this.onClick = (event) => this.select(event.currentTarget.dataset.ci);
    this.buttons.forEach((button) => button.addEventListener("click", this.onClick));
  },

  destroyed() {
    this.clearTimers();
    if (this.buttons) this.buttons.forEach((button) => button.removeEventListener("click", this.onClick));
  },

  // Switching CI cuts any typing short and shows every variant's final
  // frame; only the page load animates.
  select(ci) {
    if (!ci || this.diff.dataset.ci === ci) return;
    this.settle();
    this.diff.dataset.ci = ci;
    this.buttons.forEach((button) => {
      const selected = button.dataset.ci === ci;
      button.toggleAttribute("data-selected", selected);
      button.setAttribute("aria-pressed", String(selected));
    });
  },

  settle() {
    this.clearTimers();
    this.diff.querySelectorAll('[data-part="typed"]').forEach((span) => {
      span.textContent = span.dataset.text || span.textContent;
    });
    this.diff.removeAttribute("data-typing");
  },

  // Types the added line of the variant the diff currently shows.
  type(delay) {
    this.clearTimers();
    const typed = this.diff.querySelector(
      `[data-part="variant"][data-ci="${this.diff.dataset.ci}"] [data-part="typed"]`,
    );
    if (!typed) return;

    const text = typed.dataset.text || typed.textContent;
    typed.dataset.text = text;
    typed.textContent = "";
    this.diff.setAttribute("data-typing", "");

    const tick = (index) => {
      typed.textContent = text.slice(0, index);
      if (index < text.length) {
        const wait = MIN_TICK + Math.random() * (MAX_TICK - MIN_TICK);
        this.timers.push(window.setTimeout(() => tick(index + 1), wait));
      } else {
        // Landed: the cursor's continuous blink takes over (CSS keys it
        // off data-typing being gone).
        this.diff.removeAttribute("data-typing");
      }
    };

    this.timers.push(window.setTimeout(() => tick(1), delay));
  },

  clearTimers() {
    if (this.timers) this.timers.forEach((id) => window.clearTimeout(id));
    this.timers = [];
  },
};
