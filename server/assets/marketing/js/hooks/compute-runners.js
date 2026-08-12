/*
 * Compute illustration — the runner grid (4×6 cells), drawn on a canvas so it
 * can be alive:
 *   - idle cells are blank outlines; only active cells carry the dithered
 *     dot texture, whose dots twinkle;
 *   - a rotating random subset of cells is "active" (purple-500 border,
 *     purple-50 highlight, purple corner dot + dither);
 *   - a cell flickers when it first activates — "a task is being acquired" —
 *     then settles to a soft pulse;
 *   - the active set changes at random over time.
 *
 * Canvas overlays the scene 1:1 with the wires SVG (same coordinate space), so
 * the fan/flow lines still meet the cells. Options (data attributes, scene px):
 *   data-grid-x, data-grid-top: top-left of the grid
 *   data-cell, data-gap:        cell size + gap (4 cols × 6 rows)
 */

import { onThemeChange } from "../lib/theme.js";

const ROWS = 6;
const COLS = 4;
const TARGET = 7; // initial active count
const MIN_ACTIVE = 5;
const MAX_ACTIVE = 12;
const SWAP_MS = 2600; // how often the active set churns
const FLICKER_MS = 950; // slow flicker-in / flicker-out transition
const TICK_HZ = 18; // quantized redraw — a lively but "digital" cadence
const CELL_RADIUS = 6;
const PAD = 3; // canvas extends this far past the scene so edge strokes aren't clipped
const DITHER_PITCH = 2; // dither cell size (px) — the site's unified scale
const DITHER_DOT = 2; // full cells, so dense areas fuse like the other dithers

// 8×8 ordered Bayer matrix — same dither as the navbar/DitherTexture.
const BAYER8 = [
  0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54,
  22, 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29,
  53, 21,
];

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

function roundRect(x, y, w, h, r) {
  const p = new Path2D();
  if (p.roundRect) {
    p.roundRect(x, y, w, h, r);
    return p;
  }
  p.moveTo(x + r, y);
  p.arcTo(x + w, y, x + w, y + h, r);
  p.arcTo(x + w, y + h, x, y + h, r);
  p.arcTo(x, y + h, x, y, r);
  p.arcTo(x, y, x + w, y, r);
  p.closePath();
  return p;
}

// Tinted fills (--marketing-tint-*) are translucent color washes in dark
// mode; the draw code paints opaque [r,g,b], so flatten the resolved color
// over the page background.
function resolveFillColor(host, name) {
  const probe = document.createElement("span");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.color = `var(${name})`;
  probe.style.backgroundColor = "var(--noora-surface-background-primary)";
  host.appendChild(probe);
  const style = getComputedStyle(probe);
  const color = style.color;
  const bg = style.backgroundColor;
  probe.remove();
  const c = document.createElement("canvas");
  c.width = c.height = 1;
  const ctx = c.getContext("2d");
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, 1, 1);
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 1, 1);
  const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
  return [r, g, b];
}

export const RunnerGrid = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const d = this.el.dataset;
    this.gridX = Number(d.gridX);
    this.gridTop = Number(d.gridTop);
    this.cell = Number(d.cell);
    this.gap = Number(d.gap);

    const host = this.canvas.parentElement;
    this.resolveColors = () => {
      this.cBorder = resolveTokenColor(host, "--marketing-illustration-neutral-4");
      this.cPurple = resolveTokenColor(host, "--noora-purple-500");
      this.cPurple50 = resolveFillColor(host, "--marketing-tint-purple");
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.render(this.lastSwap || 0);
    });
    // Active dither reuses the cache chart's recipe — purple-50 light dots,
    // purple-500 deep dots at low alpha — so both sections read identically.

    this.cells = [];
    for (let r = 0; r < ROWS; r++) {
      for (let c = 0; c < COLS; c++) {
        this.cells.push({
          x: this.gridX + c * (this.cell + this.gap),
          // + PAD: the canvas is offset up by PAD (see CSS) so edge strokes fit.
          y: this.gridTop + r * (this.cell + this.gap) + PAD,
          active: false,
          changeAt: -9999, // when active last flipped (drives flicker in/out)
          seed: Math.random(),
        });
      }
    }
    this.path = new Map(); // cached rounded-rect path per cell
    const illustration = this.canvas.closest('[data-part="illustration"]');
    this.runnerStat = illustration && illustration.querySelector('[data-stat="runners"]');
    this.seedActive();
    this.updateRunnerStat();
    this.lastSwap = 0;

    this.resize = () => {
      const rect = this.canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.render(0);
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
      this.update(now);
      this.render(now);
    };
    this.raf = requestAnimationFrame(tick);
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.observer) this.observer.disconnect();
  },

  rgba([r, g, b], a) {
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  },

  lerp(a, b, t) {
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  },

  shuffle(arr) {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  },

  seedActive() {
    this.cells.forEach((c) => (c.active = false));
    for (const c of this.shuffle([...this.cells]).slice(0, TARGET)) {
      c.active = true;
      c.changeAt = -9999; // already settled at load (no flicker)
    }
  },

  // Churn the active set gently, letting the count drift within bounds so the
  // "Runners" stat varies. Each change flickers in/out (never a jump), and only
  // fully-settled cells are touched.
  update(now) {
    if (now - this.lastSwap < SWAP_MS) return;
    const settled = (c) => now - c.changeAt >= FLICKER_MS;
    const active = this.cells.filter((c) => c.active && settled(c));
    const idle = this.cells.filter((c) => !c.active && settled(c));
    const count = this.cells.filter((c) => c.active).length;

    let act, deact;
    const r = Math.random();
    if (count <= MIN_ACTIVE) [act, deact] = [true, false];
    else if (count >= MAX_ACTIVE) [act, deact] = [false, true];
    else if (r < 0.35) [act, deact] = [true, false];
    else if (r < 0.7) [act, deact] = [false, true];
    else [act, deact] = [true, true]; // swap

    let changed = false;
    if (deact && active.length) {
      const c = active[Math.floor(Math.random() * active.length)];
      c.active = false;
      c.changeAt = now;
      changed = true;
    }
    if (act && idle.length) {
      const c = idle[Math.floor(Math.random() * idle.length)];
      c.active = true;
      c.changeAt = now;
      changed = true;
    }
    if (changed) {
      this.lastSwap = now;
      this.updateRunnerStat();
    }
  },

  updateRunnerStat() {
    if (!this.runnerStat) return;
    // Zero-pad to 2 digits so the stat width is constant (no reflow).
    this.runnerStat.textContent = String(this.cells.filter((c) => c.active).length).padStart(2, "0");
  },

  // Level 0..1 for a cell: a slow flicker envelope while transitioning
  // (in or out), then a settled soft pulse (on) or 0 (off).
  cellLevel(cell, now) {
    const age = now - cell.changeAt;
    if (age >= FLICKER_MS) {
      return cell.active ? 0.75 + 0.25 * Math.sin(now * 0.004 + cell.seed * 10) : 0;
    }
    const p = age / FLICKER_MS;
    const env = cell.active ? p : 1 - p; // rise (in) or fall (out)
    const flick = 0.62 + 0.38 * Math.sin(p * Math.PI * 3 + cell.seed * 6);
    return Math.max(0, env * flick);
  },

  render(now) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.w, this.h);
    for (const cell of this.cells) this.drawCell(cell, now);
  },

  drawCell(cell, now) {
    const ctx = this.ctx;
    const s = this.cell;
    let path = this.path.get(cell);
    if (!path) {
      path = roundRect(cell.x, cell.y, s, s, CELL_RADIUS);
      this.path.set(cell, path);
    }

    const level = this.cellLevel(cell, now);
    if (level > 0.01) {
      ctx.fillStyle = this.rgba(this.cPurple50, 0.85 * level);
      ctx.fill(path);
    }

    if (level > 0.01) {
      ctx.save();
      ctx.clip(path);
      this.drawDither(cell, now, level);
      ctx.restore();
    }

    // Border + corner dot lerp grey → purple with the level.
    const tint = this.lerp(this.cBorder, this.cPurple, level);
    ctx.strokeStyle = this.rgba(tint, 1);
    ctx.lineWidth = 1;
    ctx.stroke(path);

    ctx.fillStyle = this.rgba(tint, 1);
    ctx.beginPath();
    ctx.arc(cell.x + s - 7.5, cell.y + 7.5, 2.5, 0, Math.PI * 2);
    ctx.fill();
  },

  // Ordered Bayer dither over a travelling wave field — the same technique as
  // the navbar dither: a dot is drawn only where the wave signal beats the 8×8
  // Bayer threshold, and its tone is dithered light/mid by a second lookup.
  // Bayer + wave use GLOBAL coords so the pattern is continuous across cells.
  drawDither(cell, now, level) {
    const ctx = this.ctx;
    const s = this.cell;
    // Only active cells carry dither (idle cells stay blank), so the texture
    // is always purple and fades in/out with the activation level.
    const light = this.cPurple50;
    const mid = this.cPurple;
    const lightAlpha = (0.55 + 0.45 * level) * level;
    // Deep dots settle at the chart's 0.24 stroke alpha when fully active,
    // so the texture stays a light tint like the chart's gradient.
    const midAlpha = (0.55 - 0.31 * level) * level;
    const bump = 0.16 * level; // active cells read a touch denser
    for (let dy = DITHER_PITCH; dy < s - 1; dy += DITHER_PITCH) {
      for (let dx = DITHER_PITCH; dx < s - 1; dx += DITHER_PITCH) {
        const gx = cell.x + dx;
        const gy = cell.y + dy;
        const ix = Math.round(gx / DITHER_PITCH);
        const iy = Math.round(gy / DITHER_PITCH);
        const wave = Math.sin(gx * 0.08 - now * 0.0018) + Math.sin(gy * 0.075 + now * 0.0014);
        const n = Math.min(0.95, 0.42 + 0.28 * wave + bump);
        if (BAYER8[(iy & 7) * 8 + (ix & 7)] / 64 >= n) continue;
        const depth = Math.max(0, Math.min(1, (n - 0.42) / 0.5));
        const deep = BAYER8[((iy + 4) & 7) * 8 + ((ix + 4) & 7)] / 64 < depth;
        ctx.fillStyle = this.rgba(deep ? mid : light, deep ? midAlpha : lightAlpha);
        ctx.fillRect(gx - DITHER_DOT / 2, gy - DITHER_DOT / 2, DITHER_DOT, DITHER_DOT);
      }
    }
  },
};
