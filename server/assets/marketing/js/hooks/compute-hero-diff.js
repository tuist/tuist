// Typewriter entrance for the compute hero's runs-on diff: the added
// line's code types out once per page load behind a terminal-style block
// cursor that stays solid while typing and blinks continuously once the
// line has landed. An inline first-paint script in the template arms the
// diff (stashing the line into data-text and clearing it) before the
// browser paints, so the full text never flashes ahead of the typing;
// without JS, or under reduced motion, the diff just shows its final
// frame with no cursor.

const START_DELAY = 600;
const MIN_TICK = 45;
const MAX_TICK = 110;

export const ComputeHeroDiff = {
  mounted() {
    const typed = this.el.querySelector('[data-part="typed"]');
    if (!typed) return;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      // The inline script skips arming under reduced motion too; restoring
      // here just covers the two checks ever disagreeing.
      if (this.el.hasAttribute("data-armed")) {
        typed.textContent = typed.dataset.text || typed.textContent;
        this.el.removeAttribute("data-armed");
      }
      return;
    }

    // The inline script normally arms before first paint; arming here is
    // the fallback for when it was blocked.
    if (!this.el.hasAttribute("data-armed")) {
      typed.dataset.text = typed.textContent;
      typed.textContent = "";
      this.el.setAttribute("data-armed", "");
    }

    const text = typed.dataset.text || "";
    this.timers = [];
    this.el.setAttribute("data-typing", "");

    const tick = (index) => {
      typed.textContent = text.slice(0, index);
      if (index < text.length) {
        const delay = MIN_TICK + Math.random() * (MAX_TICK - MIN_TICK);
        this.timers.push(window.setTimeout(() => tick(index + 1), delay));
      } else {
        // Landed: the cursor's continuous blink takes over (CSS keys it
        // off data-typing being gone).
        this.el.removeAttribute("data-typing");
      }
    };

    this.timers.push(window.setTimeout(() => tick(1), START_DELAY));
  },

  destroyed() {
    if (this.timers) this.timers.forEach((id) => window.clearTimeout(id));
  },
};
