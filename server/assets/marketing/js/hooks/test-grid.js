/*
 * Tests illustration — a fixed 45×12 grid of 15×15 rounded squares (8px gaps,
 * 1027×268 total), drawn on a canvas. It loops a little "test run" story:
 *
 *   1. loading  — every cell is a light grey placeholder, its shade gently
 *                 pulsing (a skeleton loader);
 *   2. resolve  — the selective cells fade to purple, then the flaky cells pop
 *                 amber a beat later; the empty cells fade out to bare outlines;
 *   3. hold     — purple + amber + blank outlines sit for a moment;
 *   4. fade     — the colours ebb away and the grey placeholders return …
 *
 * … then it loops back to loading. Each pass re-deals the cell states with
 * jittered densities, so every loop shows a different grid and different
 * counts. The clock starts on the first on-screen frame and rendering pauses
 * while the canvas is off-screen. The grid is a
 * fixed size, centred in the slightly taller stage and cropped left/right on
 * narrow viewports.
 *
 * Options (data attributes):
 *   data-cell, data-gap, data-radius: square size, spacing, corner radius
 *   data-cols, data-rows:             grid dimensions
 */

import { onThemeChange } from "../lib/theme.js";

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

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  if (ctx.roundRect) {
    ctx.roundRect(x, y, w, h, r);
    return;
  }
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

const smoothstep = (t) => {
  const c = Math.max(0, Math.min(1, t));
  return c * c * (3 - 2 * c);
};

const DRAW_INTERVAL = 45; // ms between redraws (~22fps — plenty for a shimmer)

// Loop phases (ms).
const LOAD_MS = 2200; // grey "loading" spell before any colour appears
const RESOLVE_MS = 600; // fade-in duration of a colour
const FLAKY_DELAY = 350; // flaky pops this much after the purple
const HOLD_MS = 6250; // colours held before they ebb away (the bulk of the loop)
const FADE_MS = 600; // colours fade back out to grey
const FADE_AT = LOAD_MS + FLAKY_DELAY + RESOLVE_MS + HOLD_MS; // when the fade begins
const CYCLE_MS = FADE_AT + FADE_MS; // full loop length

export const TestGrid = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const d = this.el.dataset;
    this.cell = Number(d.cell) || 15;
    this.gap = Number(d.gap) || 8;
    this.radius = Number(d.radius) || 2;
    this.cols = Number(d.cols) || 45;
    this.rows = Number(d.rows) || 12;

    const host = this.canvas.parentElement;
    this.resolveColors = () => {
      // Light neutral ramp the loading cells shimmer across (kept subtle).
      this.palette = [1, 2, 3].map((n) => resolveTokenColor(host, `--marketing-illustration-neutral-${n}`));
      this.cEmpty = resolveTokenColor(host, "--marketing-illustration-neutral-3");
      this.cSelBorder = resolveTokenColor(host, "--noora-purple-500");
      this.cSelFill = resolveFillColor(host, "--marketing-tint-purple");
      this.cFlakyBorder = resolveTokenColor(host, "--noora-yellow-600");
      this.cFlakyFill = resolveTokenColor(host, "--noora-yellow-500");
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.render(this.now);
    });

    // Shimmer params are fixed per cell; states are re-dealt every cycle.
    this.cells = [];
    for (let r = 0; r < this.rows; r++) {
      for (let c = 0; c < this.cols; c++) {
        this.cells.push({
          c,
          r,
          state: "empty",
          f1: 0.0004 + Math.random() * 0.0009,
          f2: 0.0003 + Math.random() * 0.0007,
          p1: Math.random() * Math.PI * 2,
          p2: Math.random() * Math.PI * 2,
        });
      }
    }

    this.pitch = this.cell + this.gap;
    this.gridW = this.cols * this.cell + (this.cols - 1) * this.gap;
    this.gridH = this.rows * this.cell + (this.rows - 1) * this.gap;
    this.revealStart = null; // stamped on the first on-screen frame
    this.forcedCt = null; // fixed cycle time for reduced-motion
    this.now = 0; // latest animation timestamp, so resize repaints stay in sync

    // The stats are the live square counts (skipped = blank, ran = purple,
    // flaky = amber), computed over the currently-visible columns — see
    // computeCounts().
    this.effCols = this.cols;
    this.cycleIndex = 0;
    this.shuffleStates();
    const illustration = this.canvas.closest('[data-part="illustration"]');
    this.stats = {
      skipped: illustration && illustration.querySelector('[data-stat="skipped"]'),
      ran: illustration && illustration.querySelector('[data-stat="ran"]'),
      flaky: illustration && illustration.querySelector('[data-stat="flaky"]'),
    };

    this.resize = () => {
      const rect = this.canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      // Only draw as many columns as fit the width so boxes are never cut; the
      // grid is centred and the counts follow the visible columns.
      this.effCols = Math.max(1, Math.min(this.cols, Math.floor((this.w + this.gap) / this.pitch)));
      const gridWeff = this.effCols * this.cell + (this.effCols - 1) * this.gap;
      this.offX = Math.round((this.w - gridWeff) / 2);
      this.offY = Math.round((this.h - this.gridH) / 2);
      this.computeCounts();
      this.render(this.now);
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.canvas);
    this.resize();

    if (this.reduced) {
      this.forcedCt = FADE_AT - HOLD_MS / 2; // hold: colours shown, empties blank
      this.render(0);
      return;
    }

    this.lastDraw = -Infinity;
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      if (this.canvas.checkVisibility && !this.canvas.checkVisibility()) return;
      this.now = now;
      // Start the loop the first time the grid is actually on-screen.
      if (this.revealStart == null) this.revealStart = now;
      if (now - this.lastDraw < DRAW_INTERVAL) return;
      this.lastDraw = now;
      this.render(now);
    };
    this.raf = requestAnimationFrame(tick);
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.observer) this.observer.disconnect();
  },

  // Re-deal every cell's state. Densities jitter around the reference mix
  // (~28% selective, ~2% flaky) so each loop lands on different counts, and
  // the stats recount from the fresh grid.
  shuffleStates() {
    const pFlaky = 0.015 + Math.random() * 0.02;
    const pSelective = 0.2 + Math.random() * 0.16;
    for (const cell of this.cells) {
      const r = Math.random();
      cell.state = r < pFlaky ? "flaky" : r < pFlaky + pSelective ? "selective" : "empty";
    }
    this.computeCounts();
  },

  rgba([r, g, b], a) {
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  },

  lerp(a, b, t) {
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  },

  // A colour interpolated across the neutral palette by t in [0,1].
  paletteColor(t) {
    const pal = this.palette;
    const x = Math.max(0, Math.min(1, t)) * (pal.length - 1);
    const i = Math.min(pal.length - 2, Math.floor(x));
    return this.lerp(pal[i], pal[i + 1], x - i);
  },

  // Per-cell shimmer level in [0,1] from two out-of-phase sines — a gentle,
  // never-syncing pulse so the loading grid reads like skeleton placeholders.
  shimmer(cell, now) {
    const n = Math.sin(now * cell.f1 + cell.p1) * 0.6 + Math.sin(now * cell.f2 + cell.p2) * 0.4;
    const v = n * 0.5 + 0.5;
    return Math.pow(v, 1.3);
  },

  // Where we are in the loop (ms), or the fixed reduced-motion frame. Each
  // time the loop wraps, the grid re-deals — the swap happens at the start of
  // the grey loading phase, when no colour is up, so it's invisible.
  cycleTime(now) {
    if (this.forcedCt != null) return this.forcedCt;
    if (this.revealStart == null) return 0;
    const elapsed = now - this.revealStart;
    const index = Math.floor(elapsed / CYCLE_MS);
    if (index !== this.cycleIndex) {
      this.cycleIndex = index;
      this.shuffleStates();
    }
    return elapsed % CYCLE_MS;
  },

  // Rise (after `lag`) then fall (at FADE_AT) — one bump per loop.
  envelope(ct, lag) {
    const up = smoothstep((ct - lag) / RESOLVE_MS);
    const down = smoothstep((ct - FADE_AT) / FADE_MS);
    return up * (1 - down);
  },

  // Colour intensity for a coloured cell (0 for empty). Flaky lags the purple.
  colorReveal(cell, ct) {
    if (cell.state === "empty") return 0;
    const lag = cell.state === "flaky" ? LOAD_MS + FLAKY_DELAY : LOAD_MS;
    return this.envelope(ct, lag);
  },

  // Recount over the visible columns (they shrink on narrow viewports).
  computeCounts() {
    const vis = this.cells.filter((c) => c.c < this.effCols);
    this.ranCount = vis.filter((c) => c.state === "selective").length;
    this.flakyCount = vis.filter((c) => c.state === "flaky").length;
    this.skippedCount = vis.filter((c) => c.state === "empty").length;
  },

  setStat(key, text) {
    const el = this.stats[key];
    if (el && el.textContent !== text) el.textContent = text;
  },

  // Count the stats up in step with the grid: ran/skipped track the purple
  // envelope, flaky its slightly-later one.
  updateStats(ct) {
    if (this.revealStart == null && this.forcedCt == null) return; // keep initial values
    const pMain = this.envelope(ct, LOAD_MS);
    const pFlaky = this.envelope(ct, LOAD_MS + FLAKY_DELAY);
    this.setStat("ran", String(Math.round(this.ranCount * pMain)));
    this.setStat("skipped", String(Math.round(this.skippedCount * pMain)));
    this.setStat("flaky", String(Math.round(this.flakyCount * pFlaky)));
  },

  render(now) {
    const ctx = this.ctx;
    const ct = this.cycleTime(now);
    ctx.clearRect(0, 0, this.w, this.h);
    ctx.lineWidth = 1;

    for (const cell of this.cells) {
      if (cell.c >= this.effCols) continue; // trimmed to fit the width
      const x = this.offX + cell.c * this.pitch;
      const y = this.offY + cell.r * this.pitch;
      this.drawCell(cell, x, y, now, ct);
    }
    this.updateStats(ct);
  },

  drawCell(cell, x, y, now, ct) {
    const ctx = this.ctx;
    const s = this.cell;
    const reveal = this.colorReveal(cell, ct);
    // Grey empties out in sync with the colours (empty cells use the purple
    // envelope so they blank while colours are up, then return during loading).
    const fade = cell.state === "empty" ? this.envelope(ct, LOAD_MS) : reveal;
    roundRect(ctx, x, y, s, s, this.radius);

    // Grey loading placeholder — the base for every cell; shade pulses, then
    // empties out (blank outline) or fades under a resolving colour.
    const v = this.shimmer(cell, now);
    const base = (0.3 + 0.4 * v) * (1 - fade);
    if (base > 0.01) {
      ctx.fillStyle = this.rgba(this.paletteColor(v), base);
      ctx.fill();
    }

    // Selective → purple fill fading in on top.
    if (cell.state === "selective" && reveal > 0.01) {
      ctx.fillStyle = this.rgba(this.cSelFill, reveal);
      ctx.fill();
    }

    // Border eases from the faint grey outline to the state colour.
    const colorBorder =
      cell.state === "selective" ? this.cSelBorder : cell.state === "flaky" ? this.cFlakyBorder : this.cEmpty;
    ctx.strokeStyle = this.rgba(this.lerp(this.cEmpty, colorBorder, reveal), 1);
    ctx.stroke();

    // Flaky → filled amber inner square fading in.
    if (cell.state === "flaky" && reveal > 0.01) {
      roundRect(ctx, x + 3, y + 3, s - 6, s - 6, 1);
      ctx.fillStyle = this.rgba(this.cFlakyFill, reveal);
      ctx.fill();
    }
  },
};
