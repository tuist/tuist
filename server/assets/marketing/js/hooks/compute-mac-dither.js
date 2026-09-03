/*
 * "Powerful compute, ready" card: the dot field trailing off the Mac's
 * flank. The comp bakes ~1900 dots into an SVG; here the field is
 * regenerated procedurally on canvas — a 6px grid whose presence
 * probability ramps up toward the machine's edge — so it weighs nothing,
 * follows the theme tokens, and can live: a random subset of dots
 * twinkles in and out continuously. Reduced motion renders the static
 * field once.
 *
 * Options (data attributes, canvas px): data-edge — the field's right
 * limit (the Mac body's left edge); data-top / data-bottom — vertical
 * span.
 */

import { onThemeChange } from "../lib/theme.js";

const PITCH = 6;
const TICK_HZ = 12;

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

// Deterministic per-cell hash → 0..1, so the field is identical on every
// load and repaint.
function cellRand(ix, iy, salt) {
  let h = (ix * 73856093) ^ (iy * 19349663) ^ (salt * 83492791);
  h = Math.imul(h ^ (h >>> 13), 0x5bd1e995);
  h ^= h >>> 15;
  return (h >>> 0) / 4294967296;
}

export const ComputeMacDither = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const d = this.el.dataset;
    this.edge = Number(d.edge) || 286;
    this.top = Number(d.top) || 2;
    this.bottom = Number(d.bottom) || 176;

    const host = this.canvas.parentElement;
    this.resolveColors = () => {
      this.rgb = resolveTokenColor(host, "--marketing-illustration-neutral-4");
      this.purple = resolveTokenColor(host, "--noora-purple-400");
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.render(this.lastNow || 0);
    });

    this.buildDots();

    this.resize = () => {
      const rect = this.canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.render(this.lastNow || 0);
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.canvas);
    this.resize();

    if (this.reduced) return;

    this.lastTick = -1;
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      if (this.canvas.checkVisibility && !this.canvas.checkVisibility()) return;
      const step = Math.floor((now / 1000) * TICK_HZ);
      if (step === this.lastTick) return;
      this.lastTick = step;
      this.lastNow = now;
      this.render(now);
    };
    this.raf = requestAnimationFrame(tick);
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.observer) this.observer.disconnect();
  },

  // The field: presence probability ramps toward the machine's edge, so
  // the dots read as the comp's dissolve. A third of them twinkle.
  buildDots() {
    this.dots = [];
    for (let y = this.top; y <= this.bottom; y += PITCH) {
      for (let x = PITCH; x <= this.edge; x += PITCH) {
        const ix = x / PITCH;
        const iy = Math.round(y / PITCH);
        const density = Math.pow(x / this.edge, 2.1);
        if (cellRand(ix, iy, 1) > density) continue;
        // A sparse few are purple accents; they always twinkle.
        const accent = cellRand(ix, iy, 6) < 0.05;
        this.dots.push({
          x,
          y,
          r: cellRand(ix, iy, 2) < 0.3 ? 1.05 : 0.75,
          twinkle: accent || cellRand(ix, iy, 3) < 0.35,
          accent,
          phase: cellRand(ix, iy, 4) * Math.PI * 2,
          speed: 0.0008 + cellRand(ix, iy, 5) * 0.0014,
        });
      }
    }
  },

  rgba([r, g, b], a) {
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  },

  render(now) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.w, this.h);
    for (const dot of this.dots) {
      let alpha = 0.9;
      if (dot.twinkle && !this.reduced) {
        alpha = Math.max(0, Math.sin(now * dot.speed + dot.phase)) * 0.9;
        if (alpha < 0.04) continue;
      }
      ctx.fillStyle = this.rgba(dot.accent ? this.purple : this.rgb, alpha);
      ctx.beginPath();
      ctx.arc(dot.x, dot.y, dot.r, 0, Math.PI * 2);
      ctx.fill();
    }
  },
};
