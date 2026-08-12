/*
 * Radar ping (security card): hovering the card sends ONE Bayer-dithered
 * pulse outward from the shield — not a circle, but the shield's own
 * outline expanding smoothly, computed as iso-contours of a distance field
 * around the silhouette. As the crest travels it deposits a settled dither
 * field behind it — denser near the shield, thinning outward — which stays
 * as the card's background for as long as the pointer hovers. On leave the
 * canvas clears back to blank and the ping re-arms. Under
 * prefers-reduced-motion hovering shows the settled field statically, with
 * no travelling pulse.
 *
 * Options:
 *   data-trigger: selector (closest) for the hover surface — defaults to
 *                 the canvas's parent element
 *   data-shape:   selector for an element containing the silhouette <path>s
 *   data-size:    "W H" — the paths' coordinate space; the silhouette is
 *                 drawn at that natural size, centered in the host
 */

import { onThemeChange } from "../lib/theme.js";

const BAYER8 = [
  0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54,
  22, 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29,
  53, 21,
];

// Full 2px dots on the 2px cell grid (the infra faces' chunky grain), but
// placed by the ordered Bayer threshold — a stochastic threshold clumps
// into an uneven mess, while Bayer keeps the scatter evenly spaced at any
// density.
const PITCH = 2;
const DOT = 2;
const TICK_HZ = 14; // quantized pixel-art cadence, like the other dithers
const PING_MS = 1000; // the single pulse's expansion
const CUTOFF = 0.06; // signal floor — kills the gaussian tail's stray dots
const TRAIL_PX = 36; // decay length of the wake behind the crest
const TRAIL_AMP = 0.3; // wake strength — low, so it dithers in the light shades
const AMBIENT_AMP = 0.35; // settled field density at the badge edge — a full rim
const AMBIENT_HALF = 0.4; // settled field falloff, as a fraction of maxDist
const CLEAR_PX = 4; // breathing room between the shield and the first dots

// Deterministic hash in [0, 1): the stochastic dither threshold — stable
// per cell, so the scatter never reshuffles between frames.
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

export const DitherPing = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.parentElement;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.raf = null;
    this.armed = true;
    this.settled = false;

    const shapeRoot = this.el.dataset.shape ? document.querySelector(this.el.dataset.shape) : null;
    this.paths = shapeRoot ? Array.from(shapeRoot.querySelectorAll("path")) : [];
    const size = (this.el.dataset.size || "")
      .trim()
      .split(/[\s,]+/)
      .map(Number);
    this.shapeSize = size.length === 2 && size.every((n) => n > 0) ? size : [145, 145];

    // Shallow → deep dot ramp — the transparency section's shared dither
    // tokens, so the ping matches the OSS logo's purples in both themes.
    this.resolveColors = () => {
      this.shades = [
        resolveTokenColor(this.host, "--marketing-transparency-dither-shallow"),
        resolveTokenColor(this.host, "--marketing-transparency-dither-mid"),
        resolveTokenColor(this.host, "--marketing-transparency-dither-deep"),
      ];
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      if (this.settled && this.raf === null) this.render(1);
    });

    this.resize = () => {
      const rect = this.host.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.buildDistanceField();
      if (this.settled && this.raf === null) this.render(1);
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.host);
    this.resize();

    this.onEnter = () => {
      // Reduced motion: no travelling pulse — just the settled field
      // while the pointer is over the card.
      if (this.reduced) {
        this.settled = true;
        this.render(1);
        return;
      }
      // One pulse per hover: fire only if re-armed by a previous leave.
      if (!this.armed || this.raf !== null) return;
      this.armed = false;
      this.t0 = null;
      this.lastTick = -1;
      this.raf = requestAnimationFrame(this.tick);
    };
    this.onLeave = () => {
      // Back to blank: the field only exists while hovering.
      this.armed = true;
      this.settled = false;
      if (this.raf !== null) {
        cancelAnimationFrame(this.raf);
        this.raf = null;
      }
      this.ctx.clearRect(0, 0, this.w, this.h);
    };
    this.trigger = (this.el.dataset.trigger && this.el.closest(this.el.dataset.trigger)) || this.host;
    this.trigger.addEventListener("mouseenter", this.onEnter);
    this.trigger.addEventListener("mouseleave", this.onLeave);

    this.tick = (now) => {
      this.raf = requestAnimationFrame(this.tick);
      const step = Math.floor((now / 1000) * TICK_HZ);
      if (step === this.lastTick) return;
      this.lastTick = step;
      if (this.t0 === null) this.t0 = now;
      const p = (now - this.t0) / PING_MS;
      if (p >= 1) {
        // The pulse dies but its deposit stays: settle into the ambient
        // field instead of clearing.
        cancelAnimationFrame(this.raf);
        this.raf = null;
        this.settled = true;
        this.render(1);
        return;
      }
      this.render(p);
    };
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.observer) this.observer.disconnect();
    if (this.raf !== null) cancelAnimationFrame(this.raf);
    this.trigger.removeEventListener("mouseenter", this.onEnter);
    this.trigger.removeEventListener("mouseleave", this.onLeave);
  },

  // Distance (in cells) from every cell to the shield silhouette, so the
  // pulse's iso-lines are outward offsets of the shield outline itself.
  // Two-pass 1 / √2 chamfer transform over the rasterized silhouette.
  buildDistanceField() {
    this.dist = null;
    if (!this.paths.length || !this.w || !this.h) return;
    const cols = Math.ceil(this.w / PITCH);
    const rows = Math.ceil(this.h / PITCH);
    const c = document.createElement("canvas");
    c.width = cols;
    c.height = rows;
    const sctx = c.getContext("2d");
    // Silhouette at natural size, centered in the host, at cell resolution.
    sctx.scale(1 / PITCH, 1 / PITCH);
    sctx.translate((this.w - this.shapeSize[0]) / 2, (this.h - this.shapeSize[1]) / 2);
    sctx.fillStyle = "#fff";
    for (const el of this.paths) {
      const d = el.getAttribute("d");
      if (d) sctx.fill(new Path2D(d));
    }
    const alpha = sctx.getImageData(0, 0, cols, rows).data;
    const INF = 1e9;
    const dist = new Float32Array(cols * rows);
    for (let i = 0; i < cols * rows; i++) {
      dist[i] = alpha[i * 4 + 3] > 127 ? 0 : INF;
    }
    const SQRT2 = Math.SQRT2;
    for (let y = 0; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        const i = y * cols + x;
        if (x > 0) dist[i] = Math.min(dist[i], dist[i - 1] + 1);
        if (y > 0) dist[i] = Math.min(dist[i], dist[i - cols] + 1);
        if (x > 0 && y > 0) dist[i] = Math.min(dist[i], dist[i - cols - 1] + SQRT2);
        if (x < cols - 1 && y > 0) dist[i] = Math.min(dist[i], dist[i - cols + 1] + SQRT2);
      }
    }
    let max = 0;
    for (let y = rows - 1; y >= 0; y--) {
      for (let x = cols - 1; x >= 0; x--) {
        const i = y * cols + x;
        if (x < cols - 1) dist[i] = Math.min(dist[i], dist[i + 1] + 1);
        if (y < rows - 1) dist[i] = Math.min(dist[i], dist[i + cols] + 1);
        if (x < cols - 1 && y < rows - 1) dist[i] = Math.min(dist[i], dist[i + cols + 1] + SQRT2);
        if (x > 0 && y < rows - 1) dist[i] = Math.min(dist[i], dist[i + cols - 1] + SQRT2);
        if (dist[i] > max && dist[i] < INF) max = dist[i];
      }
    }
    this.dist = dist;
    this.cols = cols;
    this.rows = rows;
    this.maxDist = max * PITCH;
  },

  // p in 0..1: the shield-shaped pulse travels outward, band widening a
  // little as it goes, the pulse fading out while it deposits the settled
  // ambient field behind its crest.
  render(p) {
    const { ctx, w, h, dist, cols, rows, shades } = this;
    ctx.clearRect(0, 0, w, h);
    if (!dist) return;
    const eased = 1 - (1 - p) * (1 - p);
    const radius = eased * this.maxDist;
    const band = 16 + eased * 16;
    const fade = 1 - p;
    // Once settled, the ambient field covers the whole canvas; while the
    // first pulse is still travelling it only exists behind the crest.
    const reach = this.settled ? Infinity : radius;
    const falloff = this.maxDist * AMBIENT_HALF;
    for (let y = 0; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        const d = dist[y * cols + x] * PITCH;
        if (d <= CLEAR_PX) continue; // the shield and a thin margin own this space
        const crest = Math.exp(-(((d - radius) / band) ** 2)) * 0.75;
        // Wake: a lighter tail the crest drags behind it, decaying back
        // toward the shield edge. Its low amplitude lands in the shallow
        // ramp shades, so the trail reads lighter than the crest.
        const trail = d < radius ? Math.exp(-((radius - d) / TRAIL_PX)) * TRAIL_AMP : 0;
        const pulse = Math.max(crest, trail) * fade;
        // Settled background: a steep density ramp — dense at the shield
        // edge thinning to a sparse scatter at the card's far corners. It
        // never fades while hovered — this is what remains after the burst.
        const ambient = d < reach && falloff > 0 ? Math.exp(-d / falloff) * AMBIENT_AMP : 0;
        const n = Math.max(pulse >= CUTOFF ? pulse : 0, ambient);
        if (n <= 0) continue;
        const threshold = Math.max(BAYER8[(y & 7) * 8 + (x & 7)] / 64, 0.02);
        if (threshold >= n) continue;
        // Seamless ramp: the signal maps to a continuous position across
        // the three shades, and each dot dithers between its two nearest
        // shades (independent hash channel, so it doesn't correlate with
        // the density threshold above) — the colors interleave instead of
        // stacking into visible bands.
        const s = Math.min(2, (n / 0.3) * 2);
        const lo = Math.floor(s);
        const hi = Math.min(2, lo + 1);
        const shade = s - lo > noise2(x + 31, y + 17) ? shades[hi] : shades[lo];
        ctx.fillStyle = `rgb(${shade[0]}, ${shade[1]}, ${shade[2]})`;
        ctx.fillRect(x * PITCH, y * PITCH, DOT, DOT);
      }
    }
  },
};
