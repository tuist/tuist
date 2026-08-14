/*
 * Dither-dot field behind the customer story cards (Monzo / Trendyol).
 * The dot layout and shades are the Figma export verbatim
 * (customers-dither-dots-data.js); the canvas adds two behaviors on top:
 *
 * - At rest, every dot keeps its position and shade and gently fades in
 *   and out on its own phase, so the field breathes quietly instead of
 *   reshuffling. Phases come from a deterministic hash seeded by the
 *   element id, so the two cards drift out of sync without ever
 *   re-randomizing.
 * - Hovering the card eases each dot onto one of the card's three solid
 *   brand shades (the --marketing-customers-dither-hover-{strong,mid,soft}
 *   tokens), hashed per dot so the colored state stays dithered, while
 *   each column's top dots fade out top-first — the columns read as
 *   getting shorter: the build-time drop the caption talks about. The
 *   slow flicker keeps breathing through the hover state.
 *
 * Static (and hover-snapping) under prefers-reduced-motion; re-resolves
 * colors on theme change.
 */

import { onThemeChange } from "../lib/theme.js";
import { DOTS, HEIGHT, WIDTH } from "./customers-dither-dots-data.js";

const PERIOD_MS = 6000; // one full fade-out-and-back per dot
const BASE_ALPHA = 0.65; // midpoint of the fade
const AMPLITUDE = 0.35; // fade swing around the midpoint
const HOVER_MS = 250; // ease-in/out duration of the hover state
const TAU = Math.PI * 2;

// Deterministic hash in [0, 1): gives each dot a stable flicker phase and
// hover alpha.
function noise2(x, y) {
  let h = (Math.imul(x + 1, 374761393) + Math.imul(y + 1, 668265263)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

function resolveTokenColor(host, name) {
  const probe = document.createElement("span");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.color = `var(${name})`;
  host.appendChild(probe);
  const resolved = getComputedStyle(probe).color;
  probe.remove();
  const c = document.createElement("canvas");
  c.width = c.height = 1;
  const ctx = c.getContext("2d");
  ctx.fillStyle = resolved;
  ctx.fillRect(0, 0, 1, 1);
  const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
  return [r, g, b];
}

export const CustomersDitherDots = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.parentElement;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    // Per-card seed from the element id so the side-by-side cards don't
    // flicker in lockstep.
    this.seed = 0;
    for (const ch of this.el.id) this.seed = (Math.imul(this.seed, 31) + ch.charCodeAt(0)) | 0;

    // Densify the export a touch: walk each column's 8px rhythm from its
    // topmost dot and drop a filler dot into some of the empty cells —
    // hash-gated so the field stays dithered, mostly shallow so the
    // export's own dots keep the lead. Fillers join the base list and get
    // the same flicker/hover/shrink treatment.
    const occupied = new Set(DOTS.map(([x, y]) => `${x},${y}`));
    const columnYs = new Map();
    for (const [x, y] of DOTS) {
      if (!columnYs.has(x)) columnYs.set(x, []);
      columnYs.get(x).push(y);
    }
    const extras = [];
    // Hover-only sprinkle: dots from the still-empty cells that fade in
    // (staggered) as the columns retreat, so the hover state trades
    // height for a little extra sparkle.
    this.hoverExtras = [];
    for (const [x, ys] of columnYs) {
      const top = Math.min(...ys);
      for (let y = top + 8; y <= HEIGHT - 4; y += 8) {
        let taken = false;
        for (let o = -2; o <= 2 && !taken; o++) taken = occupied.has(`${x},${y + o}`);
        if (taken) continue;
        if (noise2(x * 7, y) < 0.5) {
          extras.push([x, y, noise2(x, y + 1) < 0.75 ? 0 : 1]);
        } else if (noise2(x * 13, y) < 0.5) {
          this.hoverExtras.push({
            x,
            y,
            tier: noise2(x, y + 3) < 0.5 ? 1 : 2,
            order: noise2(x * 3, y) * 0.7,
            step: 0.3,
            phase: noise2(x, y + 9) * TAU,
          });
        }
      }
    }
    this.dots = DOTS.concat(extras);

    this.phases = this.dots.map((_, i) => noise2(i + this.seed, 0) * TAU);
    // Per-dot hover shade: mid dots land on the strong or mid solid brand
    // shade, shallow dots on mid or soft, so the hover state keeps its
    // dithered depth without fading dots toward the background.
    this.hoverTiers = this.dots.map(([, , shade], i) => {
      const h = noise2(i + this.seed, 7);
      if (shade === 1) return h < 0.6 ? 0 : 1;
      return h < 0.5 ? 1 : 2;
    });
    // Hover shrink: each column's top dots fade out top-first as the
    // hover progress eases 0 → 1, with each dot claiming a slice of the
    // progress so the retreat climbs down the column. The retreat depth
    // (2–6 dots) hashes off the card seed, and a few seeded dropouts
    // below the retreat wink out at random points of the hover, so the
    // two cards shrink into visibly different silhouettes. Every column
    // keeps at least one dot so the field never empties.
    const columns = new Map();
    this.dots.forEach(([x], i) => {
      if (!columns.has(x)) columns.set(x, []);
      columns.get(x).push(i);
    });
    this.shrink = new Map(); // dot index → its stagger slice of the hover
    let col = 0;
    for (const indices of columns.values()) {
      indices.sort((a, b) => this.dots[a][1] - this.dots[b][1]);
      const desired = 2 + Math.floor(noise2(col + this.seed, 13) * 5);
      const count = Math.min(desired, Math.max(indices.length - 1, 0));
      for (let k = 0; k < count; k++) {
        this.shrink.set(indices[k], { order: k / count, step: 1 / count });
      }
      col++;
    }
    this.dots.forEach((_, i) => {
      if (this.shrink.has(i)) return;
      if (noise2(i + this.seed, 29) < 0.12) {
        this.shrink.set(i, { order: noise2(i + this.seed, 31) * 0.8, step: 0.2 });
      }
    });

    // Hover progress (0 rest → 1 brand-colored), eased in the tick loop;
    // snapped directly under reduced motion.
    this.hover = 0;
    this.hoverTarget = 0;
    this.card = this.canvas.closest('[data-part="story"]') || this.host;
    this.onEnter = () => {
      this.hoverTarget = 1;
      if (this.reduced) {
        this.hover = 1;
        this.render(0);
      }
    };
    this.onLeave = () => {
      this.hoverTarget = 0;
      if (this.reduced) {
        this.hover = 0;
        this.render(0);
      }
    };
    this.card.addEventListener("mouseenter", this.onEnter);
    this.card.addEventListener("mouseleave", this.onLeave);

    this.resolveColors = () => {
      this.shades = [
        resolveTokenColor(this.host, "--marketing-customers-dither-shallow"),
        resolveTokenColor(this.host, "--marketing-customers-dither-mid"),
      ];
      this.hoverShades = [
        resolveTokenColor(this.host, "--marketing-customers-dither-hover-strong"),
        resolveTokenColor(this.host, "--marketing-customers-dither-hover-mid"),
        resolveTokenColor(this.host, "--marketing-customers-dither-hover-soft"),
      ];
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.render(this.lastNow || 0);
    });

    // The canvas spans the card's width at a fixed 180px height; the
    // artwork stays at its natural size and tiles to fill (see render).
    this.resize = () => {
      const rect = this.canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      this.w = Math.max(1, Math.round(rect.width));
      this.canvas.width = this.w * dpr;
      this.canvas.height = HEIGHT * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.render(this.lastNow || 0);
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.canvas);
    this.resize();

    if (this.reduced) return;

    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      if (this.canvas.checkVisibility && !this.canvas.checkVisibility()) return;
      const dt = this.lastNow ? now - this.lastNow : 16;
      this.lastNow = now;
      const step = dt / HOVER_MS;
      this.hover = this.hoverTarget > this.hover ? Math.min(1, this.hover + step) : Math.max(0, this.hover - step);
      this.render(now);
    };
    this.raf = requestAnimationFrame(tick);
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.observer) this.observer.disconnect();
    if (this.card) {
      this.card.removeEventListener("mouseenter", this.onEnter);
      this.card.removeEventListener("mouseleave", this.onLeave);
    }
  },

  render(now) {
    const { ctx, shades, phases, hoverShades, hover } = this;
    // Derive the logical width from the backing store rather than the last
    // measurement, so the drawn field always fills exactly the pixels the
    // canvas has — a stale measurement can scale it but never crop it.
    const dpr = window.devicePixelRatio || 1;
    const w = this.canvas.width / dpr;
    ctx.clearRect(0, 0, w, HEIGHT);
    const angle = (now / PERIOD_MS) * TAU;
    // The 600px artwork sits centered; wider cards are filled by tiling
    // copies outward, mirrored on odd tiles so the seams stay continuous.
    const base = (w - WIDTH) / 2;
    const tMin = Math.floor(-base / WIDTH);
    const tMax = Math.ceil((w - base) / WIDTH) - 1;
    for (let t = tMin; t <= tMax; t++) {
      const mirrored = ((t % 2) + 2) % 2 === 1;
      const tileX = base + t * WIDTH;
      // A small per-tile phase drift keeps the copies from flickering in
      // unison.
      const drift = t * 1.7;
      for (let i = 0; i < this.dots.length; i++) {
        const [x, y, shade] = this.dots[i];
        const flicker = this.reduced ? 1 : BASE_ALPHA + AMPLITUDE * Math.sin(angle + phases[i] + drift);
        const grey = shades[shade];
        // Each dot eases from its grey toward its hashed solid brand
        // shade — depth comes from the shade ramp, not from fading the
        // dots out — while the flicker keeps breathing through it.
        const target = hoverShades[this.hoverTiers[i]];
        const r = grey[0] + (target[0] - grey[0]) * hover;
        const g = grey[1] + (target[1] - grey[1]) * hover;
        const b = grey[2] + (target[2] - grey[2]) * hover;
        let alpha = flicker;
        const retreat = this.shrink.get(i);
        if (retreat && hover > 0) {
          const hidden = Math.min(1, Math.max(0, (hover - retreat.order) / retreat.step));
          alpha *= 1 - hidden;
          if (alpha <= 0) continue;
        }
        ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`;
        ctx.fillRect(tileX + (mirrored ? WIDTH - 2 - x : x), y, 2, 2);
      }
      if (hover > 0) {
        for (const d of this.hoverExtras) {
          const reveal = Math.min(1, Math.max(0, (hover - d.order) / d.step));
          if (reveal === 0) continue;
          const flicker = this.reduced ? 1 : BASE_ALPHA + AMPLITUDE * Math.sin(angle + d.phase + drift);
          const c = hoverShades[d.tier];
          ctx.fillStyle = `rgba(${c[0]}, ${c[1]}, ${c[2]}, ${flicker * reveal})`;
          ctx.fillRect(tileX + (mirrored ? WIDTH - 2 - d.x : d.x), d.y, 2, 2);
        }
      }
    }
  },
};
