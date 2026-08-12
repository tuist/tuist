/*
 * Dithered line graph behind the Trendyol customer story card — the
 * companion to customers-dither-dots.js (Monzo), sharing its grain,
 * tokens, and hover conventions.
 *
 * A metric line wanders across the card in 2px dither dots — just the
 * line, no fill. At rest it drifts almost level and every dot breathes on
 * the slow shared flicker. Hovering the card eases the line into a steep
 * descent — the build-time drop the caption talks about — while each dot
 * lands on one of the card's three solid brand shades (the
 * --marketing-customers-dither-hover-{strong,mid,soft} tokens). The whole
 * drawing is deterministic off the element-id seed; static (and
 * hover-snapping) under prefers-reduced-motion; re-resolves colors on
 * theme change.
 */

import { onThemeChange } from "../lib/theme.js";

const HEIGHT = 180; // matches the dot field's band
const PITCH = 4; // px between line dots; the 2px grain on a 4px beat
const PERIOD_MS = 6000; // one full fade-out-and-back per dot
const BASE_ALPHA = 0.65; // midpoint of the fade
const AMPLITUDE = 0.35; // fade swing around the midpoint
const HOVER_MS = 300; // ease duration of the drop — snappy, like the Monzo field
const TAU = Math.PI * 2;

// Deterministic hash in [0, 1): stable per (column, row), so the graph
// never reshuffles between frames.
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

const snap = (y) => Math.round(y / 2) * 2;
const smoothstep = (t) => t * t * (3 - 2 * t);

export const CustomersDitherLine = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.parentElement;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.seed = 0;
    for (const ch of this.el.id) this.seed = (Math.imul(this.seed, 31) + ch.charCodeAt(0)) | 0;

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
      this.hover =
        this.hoverTarget > this.hover ? Math.min(1, this.hover + step) : Math.max(0, this.hover - step);
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
    const { ctx, shades, hoverShades, hover, seed } = this;
    const dpr = window.devicePixelRatio || 1;
    const w = this.canvas.width / dpr;
    ctx.clearRect(0, 0, w, HEIGHT);
    const angle = (now / PERIOD_MS) * TAU;
    // `mix` picks between the grey shade (0) and the solid brand shade
    // (1): resting dots stay grey and migrated dots land fully branded,
    // so the color change travels with each particle.
    const dot = (x, y, tier, hoverTier, alpha, mix) => {
      const c = shades[tier];
      const target = hoverShades[hoverTier];
      const r = c[0] + (target[0] - c[0]) * mix;
      const g = c[1] + (target[1] - c[1]) * mix;
      const b = c[2] + (target[2] - c[2]) * mix;
      ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`;
      ctx.fillRect(x, y, 2, 2);
    };
    for (let gx = 0; gx < w; gx += PITCH) {
      const ix = gx / PITCH;
      const t = gx / w;
      // Rest: a near-level wander with a hint of decline. Hover: the same
      // wiggle riding a steep smoothstep descent.
      const wiggle = 12 * Math.sin(gx * 0.013 + seed) + (noise2(ix + seed, 3) - 0.5) * 8;
      const yRest = snap(56 + t * 14 + wiggle);
      const yDrop = snap(34 + 118 * smoothstep(t) + wiggle * 0.5);
      // Each dot flickers on its own phase; the swing calms while hovered.
      const amp = AMPLITUDE * (1 - 0.5 * hover);
      const flicker = this.reduced ? 1 : BASE_ALPHA + amp * Math.sin(angle + noise2(ix + seed, 5) * TAU);
      // Each dot travels vertically on hover: its column claims a hashed
      // start within the hover progress, then the dot descends from its
      // rest height to its drop height (and back up on leave) at a
      // constant rate, quantized to the 2px grain — it shifts down row by
      // row, no easing, no gliding between rows.
      const r = Math.min(1, Math.max(0, (hover - noise2(ix + seed, 15) * 0.5) / 0.5));
      const y = snap(yRest + (yDrop - yRest) * r);
      // The line itself: a mid dot, with hashed halo dots one empty grain
      // cell above and below — offset 4, a full beat, so the dots stay
      // discrete squares instead of fusing into little bars. Hovered,
      // each dot lands on a hashed solid brand shade — line dots strong
      // or mid, halo dots mid or soft — colors ride the same per-dot
      // descent, so a dot turns orange as it drops.
      const hLine = noise2(ix + seed, 11) < 0.6 ? 0 : 1;
      const hHalo = noise2(ix + seed, 13) < 0.5 ? 1 : 2;
      dot(gx, y, 1, hLine, flicker, r);
      if (noise2(ix + seed, 7) < 0.4) dot(gx, y - 4, 0, hHalo, flicker * 0.8, r);
      if (noise2(ix + seed, 9) < 0.4) dot(gx, y + 4, 0, hHalo, flicker * 0.8, r);
    }
  },
};
