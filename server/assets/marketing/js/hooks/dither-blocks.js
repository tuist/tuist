/*
 * Scatter of Bayer-dithered squares — evenly distributed, non-overlapping,
 * random side and density — with an optional shimmer: dots near each
 * square's density threshold flicker on a quantized tick, so the texture
 * twinkles without the squares themselves moving.
 *
 * Canvas-2D. The block layout is seeded and immutable; only the per-cell
 * threshold jitter advances. Redraws on resize/theme change, pauses while
 * off-screen, and stays static under prefers-reduced-motion.
 *
 * Mount on a <canvas> absolutely positioned inside the area to fill.
 *
 * Options (data attributes):
 *   data-seed:        RNG seed so a canvas keeps its exact mosaic across
 *                     renders (default: hashed from the element id)
 *   data-blocks:      number of rectangles (default 26)
 *   data-pitch:       dither cell size in CSS px (default 4)
 *   data-dot:         dot size inside the cell in CSS px (default 2)
 *   data-opacity:     dot opacity, 0..1 (default 1)
 *   data-colors:      comma-separated CSS custom property names; each block
 *                     picks one at random (default the light end of the
 *                     marketing illustration ramp)
 *   data-shimmer:     "on" | "off" (default on)
 *   data-shimmer-amp: threshold jitter amplitude, 0..1 — how wide a band of
 *                     dots participates in the flicker (default 0.12)
 *   data-shimmer-hz:  shimmer tick rate (default 8)
 */

import { onThemeChange } from "../lib/theme.js";

const BAYER8 = [
  0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54,
  22, 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29,
  53, 21,
];

const DEFAULT_COLORS = [
  "--marketing-illustration-neutral-1",
  "--marketing-illustration-neutral-2",
  "--marketing-illustration-neutral-3",
];

// Deterministic PRNG (mulberry32) so the mosaic is stable per seed.
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hashString(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

// Cheap stateless per-cell hash for the shimmer jitter.
function cellHash(x, y, t) {
  const v = Math.sin(x * 12.9898 + y * 78.233 + t * 37.719) * 43758.5453;
  return v - Math.floor(v);
}

// Resolve a CSS custom property to a concrete color string in this element's
// context (theme-dependent, so re-resolved on every layout pass).
function resolveTokenColor(host, name) {
  const probe = document.createElement("span");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.color = `var(${name})`;
  host.appendChild(probe);
  const resolved = getComputedStyle(probe).color;
  probe.remove();
  return resolved;
}

export const DitherBlocks = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");

    this.seed = parseInt(this.el.dataset.seed, 10);
    if (Number.isNaN(this.seed)) this.seed = hashString(this.el.id || "dither-blocks");
    this.blockCount = parseInt(this.el.dataset.blocks || "26", 10);
    this.pitch = parseFloat(this.el.dataset.pitch || "4");
    this.dot = parseFloat(this.el.dataset.dot || "2");
    this.opacity = parseFloat(this.el.dataset.opacity || "1");
    this.colorNames = (this.el.dataset.colors || DEFAULT_COLORS.join(",")).split(",").map((s) => s.trim());

    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.shimmer = (this.el.dataset.shimmer || "on") !== "off" && !this.reducedMotion;
    this.shimmerAmp = parseFloat(this.el.dataset.shimmerAmp || "0.12");
    this.shimmerHz = parseFloat(this.el.dataset.shimmerHz || "8");
    this.tick = 0;
    this.visible = true;

    this.layout = this.layout.bind(this);
    this.frame = this.frame.bind(this);

    this.resizeObserver = new ResizeObserver(this.layout);
    this.resizeObserver.observe(this.canvas.parentElement || this.canvas);
    this.unsubscribeTheme = onThemeChange(this.layout);

    // Shimmering off-screen is wasted work; pause until scrolled into view.
    this.intersectionObserver = new IntersectionObserver((entries) => {
      this.visible = entries[0].isIntersecting;
      if (this.visible) this.schedule();
    });
    this.intersectionObserver.observe(this.canvas);

    this.layout();
  },

  destroyed() {
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.intersectionObserver) this.intersectionObserver.disconnect();
    if (this.unsubscribeTheme) this.unsubscribeTheme();
  },

  // Recompute canvas size, colors and the seeded block layout, then render.
  layout() {
    const host = this.canvas.parentElement || this.canvas;
    const rect = host.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return;

    const dpr = window.devicePixelRatio || 1;
    this.cssWidth = rect.width;
    this.cssHeight = rect.height;
    this.canvas.width = Math.round(rect.width * dpr);
    this.canvas.height = Math.round(rect.height * dpr);
    this.dpr = dpr;

    const colors = this.colorNames.map((name) => resolveTokenColor(host, name));
    const rng = mulberry32(this.seed);
    const cols = Math.ceil(rect.width / this.pitch);
    const rows = Math.ceil(rect.height / this.pitch);
    this.cols = cols;
    this.rows = rows;

    // Squares only, no overlaps, spread evenly: carve the canvas into a
    // grid of slots one max-square wide (no margin), seeded-shuffle the
    // slots, and drop one square into each of the first N. Squares are
    // corner-aligned inside their slot, so neighbors in adjacent slots
    // butt against each other and merge into bigger patches, like the
    // reference mosaic.
    const maxSide = 12;
    const slotCells = maxSide;
    const slotCols = Math.max(1, Math.floor(cols / slotCells));
    const slotRows = Math.max(1, Math.floor(rows / slotCells));
    const slots = [];
    for (let sy = 0; sy < slotRows; sy++) {
      for (let sx = 0; sx < slotCols; sx++) slots.push([sx, sy]);
    }
    for (let i = slots.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [slots[i], slots[j]] = [slots[j], slots[i]];
    }

    // Uniform squares: every block fills its slot exactly, so neighboring
    // blocks always merge seamlessly into the patchwork.
    this.blocks = [];
    for (const [sx, sy] of slots.slice(0, this.blockCount)) {
      const density = 0.06 + rng() * 0.85;
      const color = colors[Math.floor(rng() * colors.length)] || colors[0];
      this.blocks.push({ bx: sx * slotCells, by: sy * slotCells, bw: maxSide, bh: maxSide, density, color });
    }

    this.render();
    this.schedule();
  },

  schedule() {
    if (!this.shimmer || !this.visible || this.raf) return;
    this.raf = requestAnimationFrame(this.frame);
  },

  frame(now) {
    this.raf = null;
    if (!this.visible) return;
    const tick = Math.floor((now / 1000) * this.shimmerHz);
    if (tick !== this.tick) {
      this.tick = tick;
      this.render();
    }
    this.schedule();
  },

  render() {
    if (!this.blocks) return;
    const ctx = this.ctx;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.clearRect(0, 0, this.cssWidth, this.cssHeight);
    ctx.globalAlpha = this.opacity;

    const amp = this.shimmer ? this.shimmerAmp : 0;
    const pitch = this.pitch;

    for (const block of this.blocks) {
      // Later blocks replace what's beneath them, keeping edges crisp.
      ctx.clearRect(block.bx * pitch, block.by * pitch, block.bw * pitch, block.bh * pitch);
      ctx.fillStyle = block.color;

      const x0 = Math.max(0, block.bx);
      const x1 = Math.min(this.cols, block.bx + block.bw);
      const y0 = Math.max(0, block.by);
      const y1 = Math.min(this.rows, block.by + block.bh);

      for (let y = y0; y < y1; y++) {
        for (let x = x0; x < x1; x++) {
          let threshold = BAYER8[(y % 8) * 8 + (x % 8)] / 64;
          if (amp > 0) threshold += (cellHash(x, y, this.tick) - 0.5) * amp;
          if (threshold < block.density) {
            ctx.fillRect(x * pitch, y * pitch, this.dot, this.dot);
          }
        }
      }
    }

    ctx.globalAlpha = 1;
  },
};
