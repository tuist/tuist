// Background lollipop chart for the cache page hero, drawn entirely on one
// canvas: the flat grey "COLD" row, the "CACHED" staircase on the purple
// ramp, the one-shot entrance, and the pointer-repel springs.
//
// Timeline (plays once): every column rises from below the hero, staggered
// left to right; then the cached columns drop into the staircase, tinting
// from grey to their purple ramp step as they fall; the COLD/CACHED labels
// fade in last, and that is also the moment the pointer interaction arms —
// hover stays off while the bars are animating in.
//
// Interaction: columns near the cursor stretch up when the pointer is
// below their node and dip down when it is above, and their heads sway
// sideways away from it — stems are drawn base-to-head, so they lean like
// parting grass (Stripe-style). Both axes run on an underdamped spring for
// a bouncy settle. Under reduced motion the entrance is skipped and the
// repel snaps instead of springing.
//
// Perf: one rAF loop that only runs while the entrance is playing or a
// spring is in motion — a parked pointer and a finished chart cost zero.
// Colors resolve to raw RGB once per theme (probe pattern shared with the
// other canvas hooks) and the hook repaints on tuist:theme-change.
//
// The chart boots eagerly at bundle evaluation (full page loads) instead
// of waiting for the LiveSocket to connect and mount the hook — the
// element is phx-update="ignore", so the running instance survives the
// dead-to-connected patch and the hook simply adopts it on mount.

import { onThemeChange } from "../lib/theme.js";

const NODE_SIZE = 12;
const COLD_NODE_TOP = 44;
const DROP_MIN = 60;
const DROP_MAX = 355;
const RISE_DURATION = 800;
const RISE_STAGGER = 40;
const DROP_START = 1600;
const DROP_DURATION = 1800;
const DROP_STAGGER = 120;
const LABEL_FADE = 400;
const COLD_LABEL_TOP = 12;
const CACHED_LABEL_TOP = 72;

const REPEL_RADIUS = 180;
const REPEL_STRENGTH = 44;
const SWAY_STRENGTH = 28;
// Underdamped spring (react-spring-ish "wobbly"): visible overshoot.
const STIFFNESS = 170;
const DAMPING = 12;
const REST_DELTA = 0.05;

// Light theme walks purple 100 -> 400 (50 is too faint on the light
// surface); dark theme needs darker shades (the light end glows on the
// dark surface), so it walks 800 -> 400 instead. Greys and labels are the
// two halves of --marketing-illustration-neutral-3.
const PALETTES = {
  light: {
    grey: "--noora-neutral-light-400",
    label: "--noora-neutral-light-400",
    purples: [
      "--noora-purple-100",
      "--noora-purple-200",
      "--noora-purple-200",
      "--noora-purple-300",
      "--noora-purple-400",
    ],
  },
  dark: {
    grey: "--noora-neutral-dark-800",
    label: "--noora-neutral-dark-800",
    purples: [
      "--noora-purple-800",
      "--noora-purple-700",
      "--noora-purple-600",
      "--noora-purple-500",
      "--noora-purple-400",
    ],
  },
};

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

function easeOutCubic(p) {
  return 1 - (1 - p) ** 3;
}

function rgba([r, g, b], alpha) {
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

const scratchColor = [0, 0, 0];

function mix(from, to, t) {
  scratchColor[0] = Math.round(from[0] + (to[0] - from[0]) * t);
  scratchColor[1] = Math.round(from[1] + (to[1] - from[1]) * t);
  scratchColor[2] = Math.round(from[2] + (to[2] - from[2]) * t);
  return scratchColor;
}

class HeroChart {
  constructor(el) {
    this.el = el;
    this.canvas = this.el.querySelector("canvas");
    this.ctx = this.canvas.getContext("2d", { desynchronized: true });
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.pointer = null;
    this.frame = null;
    this.lastTick = null;
    this.startedAt = null;

    const columnCount = parseInt(this.el.dataset.columns, 10) || 20;
    const coldCount = Math.floor(columnCount / 2);
    const cachedCount = columnCount - coldCount;

    this.columns = Array.from({ length: columnCount }, (_, index) => {
      const cachedIndex = index - coldCount;
      const cached = cachedIndex >= 0;
      const progress = cached && cachedCount > 1 ? cachedIndex / (cachedCount - 1) : 0;

      return {
        cached,
        drop: cached ? DROP_MIN + (DROP_MAX - DROP_MIN) * progress : 0,
        rampIndex: cached ? Math.min(Math.floor((cachedIndex * 5) / cachedCount), 4) : 0,
        riseStart: index * RISE_STAGGER,
        dropStart: DROP_START + Math.max(cachedIndex, 0) * DROP_STAGGER,
        x: 0,
        // Spring state: vertical stretch / sideways sway at the node, px.
        y: 0,
        vy: 0,
        s: 0,
        vs: 0,
      };
    });

    this.coldCount = coldCount;
    this.labelStart = DROP_START + (cachedCount - 1) * DROP_STAGGER + DROP_DURATION;
    this.timelineEnd = this.labelStart + LABEL_FADE + 200;
    // What resize() repaints before the first tick (and mid-timeline it
    // holds the last drawn frame's clock).
    this.lastElapsed = this.reducedMotion ? this.timelineEnd : 0;

    this.resolveColors();
    this.resize();

    this.unsubscribeTheme = onThemeChange(() => {
      this.resolveColors();
      this.startLoop();
    });

    this.resizeObserver = new ResizeObserver(() => {
      this.resize();
      this.startLoop();
    });
    this.resizeObserver.observe(this.el);

    this.onPointerMove = (event) => {
      const rect = this.el.getBoundingClientRect();
      this.pointer = { x: event.clientX - rect.left, y: event.clientY - rect.top };
      this.startLoop();
    };
    this.onPointerLeave = () => {
      this.pointer = null;
      this.startLoop();
    };

    // The chart is pointer-events: none, so the hero header (the hook
    // element's parent) is the interaction surface.
    this.surface = this.el.parentElement;
    this.surface.addEventListener("pointermove", this.onPointerMove);
    this.surface.addEventListener("pointerleave", this.onPointerLeave);

    this.startLoop();
  }

  destroy() {
    if (this.frame) window.cancelAnimationFrame(this.frame);
    this.frame = null;
    if (this.unsubscribeTheme) this.unsubscribeTheme();
    if (this.resizeObserver) this.resizeObserver.disconnect();
    if (this.surface) {
      this.surface.removeEventListener("pointermove", this.onPointerMove);
      this.surface.removeEventListener("pointerleave", this.onPointerLeave);
      this.surface = null;
    }
  }

  resolveColors() {
    const theme =
      document.documentElement.getAttribute("data-theme") ||
      (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    const palette = PALETTES[theme] || PALETTES.light;

    this.grey = resolveTokenColor(this.el, palette.grey);
    this.labelColor = resolveTokenColor(this.el, palette.label);
    this.purples = palette.purples.map((token) => resolveTokenColor(this.el, token));
  }

  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const width = this.el.clientWidth;
    const height = this.el.clientHeight;

    // Touching the backing store blanks the canvas, so skip no-op calls
    // (ResizeObserver fires once on observe, and drag-resizes fire densely).
    if (width === this.width && height === this.height && dpr === this.dpr) return;

    this.width = width;
    this.height = height;
    this.dpr = dpr;
    this.canvas.width = Math.round(width * dpr);
    this.canvas.height = Math.round(height * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const step = width / this.columns.length;
    this.columns.forEach((column, index) => {
      column.x = (index + 0.5) * step;
    });

    // Repaint synchronously: the resize blanked the bitmap, and waiting for
    // the next rAF would show a blank frame — that's the resize flicker.
    this.draw(this.lastElapsed);
  }

  startLoop() {
    if (this.frame || this.width === 0) return;
    this.lastTick = null;
    this.frame = window.requestAnimationFrame((time) => this.tick(time));
  }

  tick(time) {
    this.frame = null;
    if (this.startedAt === null) this.startedAt = time;

    // Reduced motion skips straight past the entrance timeline.
    const elapsed = this.reducedMotion ? this.timelineEnd : time - this.startedAt;
    const dt = this.lastTick ? Math.min((time - this.lastTick) / 1000, 0.032) : 1 / 60;
    this.lastTick = time;

    let springsMoving = false;

    // Hover stays off while the bars are animating in; it arms the moment
    // the COLD/CACHED labels start to appear.
    const interactive = elapsed >= this.labelStart;

    for (const column of this.columns) {
      let targetY = 0;
      let targetS = 0;

      if (interactive && this.pointer) {
        const dx = column.x - this.pointer.x;
        const t = Math.max(0, 1 - Math.abs(dx) / REPEL_RADIUS);

        if (t > 0) {
          const ease = t * t * (3 - 2 * t);
          const nodeY = COLD_NODE_TOP + column.drop + NODE_SIZE / 2;
          const direction = this.pointer.y > nodeY ? -1 : 1;
          targetY = direction * REPEL_STRENGTH * ease;

          // Odd, smooth sideways profile: zero at the cursor and at the
          // radius edge, peaking away-from-cursor at half the radius.
          const n = Math.max(-1, Math.min(1, dx / REPEL_RADIUS));
          targetS = SWAY_STRENGTH * 4 * n * (1 - Math.abs(n));
        }
      }

      if (this.reducedMotion) {
        column.y = targetY;
        column.s = targetS;
      } else {
        column.vy += (STIFFNESS * (targetY - column.y) - DAMPING * column.vy) * dt;
        column.y += column.vy * dt;
        column.vs += (STIFFNESS * (targetS - column.s) - DAMPING * column.vs) * dt;
        column.s += column.vs * dt;

        if (
          Math.abs(column.vy) > REST_DELTA ||
          Math.abs(column.y - targetY) > REST_DELTA ||
          Math.abs(column.vs) > REST_DELTA ||
          Math.abs(column.s - targetS) > REST_DELTA
        ) {
          springsMoving = true;
        } else {
          column.y = targetY;
          column.vy = 0;
          column.s = targetS;
          column.vs = 0;
        }
      }
    }

    this.lastElapsed = elapsed;
    this.draw(elapsed);

    if (elapsed < this.timelineEnd || springsMoving) {
      this.frame = window.requestAnimationFrame((nextTime) => this.tick(nextTime));
    } else {
      this.lastTick = null;
    }
  }

  draw(elapsed) {
    const ctx = this.ctx;
    const height = this.height;
    const stemLength = height - COLD_NODE_TOP - NODE_SIZE;

    ctx.clearRect(0, 0, this.width, height);

    for (const column of this.columns) {
      const riseProgress = Math.max(0, Math.min(1, (elapsed - column.riseStart) / RISE_DURATION));
      if (riseProgress === 0) continue;
      const riseOffset = (1 - easeOutCubic(riseProgress)) * (height - COLD_NODE_TOP);

      let dropOffset = 0;
      let tint = 0;

      if (column.cached) {
        const dropProgress = Math.max(0, Math.min(1, (elapsed - column.dropStart) / DROP_DURATION));
        const eased = easeOutCubic(dropProgress);
        dropOffset = column.drop * eased;
        tint = eased;
      }

      const headX = column.x + column.s;
      const headY = COLD_NODE_TOP + NODE_SIZE / 2 + riseOffset + dropOffset + column.y;
      const color = column.cached ? mix(this.grey, this.purples[column.rampIndex], tint) : this.grey;

      // Stem drawn base-to-head so sideways sway reads as a lean. The base
      // stays planted on the bottom edge — the line stretches when the head
      // rises and retracts when it drops (Stripe-style), never lifting off.
      // The Math.max keeps the base travelling with the column only while
      // it is still rising in from below the hero.
      ctx.strokeStyle = rgba(color, 0.5);
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(column.x, Math.max(height, headY + NODE_SIZE / 2 + stemLength));
      ctx.lineTo(headX, headY + NODE_SIZE / 2);
      ctx.stroke();

      ctx.fillStyle = rgba(color, 1);
      ctx.fillRect(headX - NODE_SIZE / 2, headY - NODE_SIZE / 2, NODE_SIZE, NODE_SIZE);
    }

    // Labels fade in last, riding their anchor column's spring.
    const labels = [
      { text: "COLD", column: this.columns[0], top: COLD_LABEL_TOP, delay: 0 },
      { text: "CACHED", column: this.columns[this.coldCount], top: CACHED_LABEL_TOP, delay: 100 },
    ];

    ctx.font = '14px "Geist Mono", monospace';
    ctx.textAlign = "center";
    ctx.textBaseline = "top";

    for (const label of labels) {
      const alpha = Math.max(0, Math.min(1, (elapsed - this.labelStart - label.delay) / LABEL_FADE));
      if (alpha === 0 || !label.column) continue;
      ctx.fillStyle = rgba(this.labelColor, alpha);
      ctx.fillText(label.text, label.column.x + label.column.s, label.top + label.column.y);
    }
  }
}

const instances = new Map();

function ensureChart(el) {
  let chart = instances.get(el);
  if (!chart) {
    chart = new HeroChart(el);
    instances.set(el, chart);
  }
  return chart;
}

// Eager boot on full page loads: the entrance starts at first paint-ish
// instead of a second later when the LiveSocket has connected. Client-side
// live navigations don't re-evaluate the bundle; there the hook's mounted()
// does the starting.
function boot() {
  const el = document.getElementById("marketing-cache-hero-chart");
  if (el) ensureChart(el);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot, { once: true });
} else {
  boot();
}

export const CacheHeroChart = {
  mounted() {
    this.chart = ensureChart(this.el);
  },

  destroyed() {
    if (this.chart) this.chart.destroy();
    instances.delete(this.el);
    this.chart = null;
  },
};
