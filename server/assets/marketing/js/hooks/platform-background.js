/*
 * Animates the blueprint "platform" decoration around the home hero.
 * The markup is server-rendered;
 * this hook only mutates state:
 *
 *   cache-hit   — a step-line graph that scrolls continuously left, appending
 *                 fresh random levels on the right as old ones exit
 *   kura-nodes  — circles re-roll their lit state so activity wanders
 *   edge glow   — cursor proximity recolors panel/hero/navbar hairlines via
 *                 --hx/--hy custom properties consumed by a CSS mask
 *
 * All timers respect prefers-reduced-motion (the server-rendered state is
 * the static fallback).
 */

// Step-line meter (A5). viewBox is 98×174; the line lives in the lower band
// and each level is one of METER_LEVELS discrete heights.
const METER_VB_W = 98;
const METER_STEP_W = 20;
const METER_Y_TOP = 66;
const METER_Y_BOT = 150;
const METER_LEVELS = 5;
const METER_SPEED = 13; // px/sec of leftward scroll

const KURA_LIT_CHANCE = 0.3;

export const PlatformBackground = {
  mounted() {
    this.timers = [];
    this.rafs = [];
    this.cleanups = [];

    this.setupEdgeGlow();

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    // The cache-hit graph has no server-rendered fallback, so it always draws
    // at least one static frame; only its scroll loop honours reduced motion.
    this.startCacheHit(reduced);
    if (reduced) return;

    this.startKuraNodes();
  },

  destroyed() {
    this.timers.forEach((id) => clearInterval(id));
    this.rafs.forEach((id) => cancelAnimationFrame(id));
    this.cleanups.forEach((fn) => fn());
  },

  setupEdgeGlow() {
    // Recolor targets: every panel border, the hero card's border, and the
    // navbar's bottom hairline — each draws its glow layer in CSS from the
    // --hx/--hy the cursor writes here.
    const navbar = document.getElementById("marketing-navbar");
    const targets = [
      ...this.el.querySelectorAll('[data-part="panel"]'),
      this.el.querySelector('[data-part="hero"]'),
      navbar,
    ].filter(Boolean);

    const onMove = (e) => {
      for (const t of targets) {
        const r = t.getBoundingClientRect();
        t.style.setProperty("--hx", `${e.clientX - r.left}px`);
        t.style.setProperty("--hy", `${e.clientY - r.top}px`);
      }
    };
    const onLeave = () => {
      for (const t of targets) {
        t.style.removeProperty("--hx");
        t.style.removeProperty("--hy");
      }
    };

    // Feed coordinates from both the stage and the navbar, so the hairline
    // glow also reacts while the cursor is on the navbar itself.
    const sources = navbar ? [this.el, navbar] : [this.el];
    for (const source of sources) {
      source.addEventListener("mousemove", onMove);
      source.addEventListener("mouseleave", onLeave);
    }
    this.cleanups.push(() => {
      for (const source of sources) {
        source.removeEventListener("mousemove", onMove);
        source.removeEventListener("mouseleave", onLeave);
      }
      onLeave();
    });
  },

  startCacheHit(reduced) {
    const widget = this.el.querySelector('[data-widget="cache-hit"]');
    if (!widget) return;
    const path = widget.querySelector('[data-part="line"]');
    if (!path) return;

    const yFor = (n) => METER_Y_BOT - (n / (METER_LEVELS - 1)) * (METER_Y_BOT - METER_Y_TOP);
    // Never repeat a level back-to-back, so every step has a visible riser.
    const nextLevel = (prev) => {
      let n;
      do {
        n = (Math.random() * METER_LEVELS) | 0;
      } while (n === prev);
      return n;
    };

    // One extra step on each side covers the scroll-in/out margins.
    const count = Math.ceil(METER_VB_W / METER_STEP_W) + 2;
    let lastLevel = nextLevel(-1);
    const ys = [yFor(lastLevel)];
    for (let i = 1; i < count; i++) {
      lastLevel = nextLevel(lastLevel);
      ys.push(yFor(lastLevel));
    }

    const draw = (offset) => {
      let x = -offset;
      let d = `M ${x} ${ys[0]}`;
      for (let i = 1; i < ys.length; i++) {
        x += METER_STEP_W;
        d += ` H ${x} V ${ys[i]}`;
      }
      d += ` H ${x + METER_STEP_W}`;
      path.setAttribute("d", d);
    };

    draw(0);
    if (reduced) return;

    let offset = 0;
    let last = performance.now();
    let raf;
    const tick = (now) => {
      offset += ((now - last) / 1000) * METER_SPEED;
      last = now;
      while (offset >= METER_STEP_W) {
        offset -= METER_STEP_W;
        ys.shift();
        lastLevel = nextLevel(lastLevel);
        ys.push(yFor(lastLevel));
      }
      draw(offset);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    this.cleanups.push(() => cancelAnimationFrame(raf));
  },

  startKuraNodes() {
    const widget = this.el.querySelector('[data-widget="kura-nodes"]');
    if (!widget) return;
    const nodes = widget.querySelectorAll('[data-part="row"] > span');
    if (nodes.length === 0) return;

    this.timers.push(
      setInterval(() => {
        for (let k = 0; k < 2; k++) {
          const i = (Math.random() * nodes.length) | 0;
          nodes[i].dataset.lit = String(Math.random() < KURA_LIT_CHANCE);
        }
      }, 1300),
    );
  },
};
