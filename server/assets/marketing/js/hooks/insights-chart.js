/**
 * InsightsChart: the tests page's "Know what's slowing you down" backdrop.
 *
 * Step time-series scroll continuously left to right behind the stat
 * cards — the home cache chart's seismograph walk, drawn as a solid stepped
 * outline only (no fill, no dither). One series per stat-card metric, each
 * walking inside its own band: the p90 duration (blue) rides high, test
 * runs (purple) mid, skipped (yellow) and failed (red) hug the baseline.
 *
 * Hovering a stat card highlights its series: the line eases to the
 * --insights-<name>-highlight colour and is painted on top of the others.
 *
 * Colours come from --insights-<name>-stroke / -highlight custom
 * properties on the host figure (light-dark() colours), resolved through a
 * probe element so the canvas paints exactly what CSS would, and
 * re-resolved on a runtime theme flip. The loop only runs while the canvas
 * is on screen, and reduced motion paints one static frame.
 */
import { onThemeChange } from "../lib/theme.js";

const SERIES = [
  { name: "blue", lo: 0.45, hi: 0.95 },
  { name: "purple", lo: 0.24, hi: 0.52 },
  { name: "yellow", lo: 0.05, hi: 0.24 },
  { name: "red", lo: 0.02, hi: 0.13 },
];
// Steps and speed scale with the canvas width, matching the home cache
// chart (2.5–5% of its half width per step, 6% per second).
const SCROLL_SPEED = 0.03;
const SEGMENT_MIN_WIDTH = 0.0125;
const SEGMENT_MAX_WIDTH = 0.025;
const MAX_STEP = 0.35; // largest jump between neighbouring steps, as a share of the band
const TOP_MARGIN = 24;
const BOTTOM_MARGIN = 40;
const LINE_WIDTH = 1.5;
const HIGHLIGHT_EASE = 10; // per second; ~150ms to settle

function between(min, max) {
  return min + Math.random() * (max - min);
}

function resolveColor(host, name) {
  const probe = document.createElement("span");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.color = `var(${name})`;
  host.appendChild(probe);
  const color = getComputedStyle(probe).color;
  probe.remove();
  return color;
}

const InsightsChart = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.closest("figure") || this.canvas.parentElement;
    this.frame = null;
    this.lastTime = null;
    this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    this.series = SERIES.map(({ name, lo, hi }) => ({
      name,
      lo,
      hi,
      offset: 0,
      segments: [],
      total: 0,
      stroke: "transparent",
      highlight: "transparent",
      glow: 0,
      glowTarget: 0,
    }));

    // Hovering a card lights up its series (cards carry data-color).
    this.cards = Array.from(this.host.querySelectorAll('[data-part="card"][data-color]'));
    this.onCardEnter = (event) => this.setHighlight(event.currentTarget.dataset.color);
    this.onCardLeave = () => this.setHighlight(null);
    for (const card of this.cards) {
      card.addEventListener("mouseenter", this.onCardEnter);
      card.addEventListener("mouseleave", this.onCardLeave);
    }

    this.resizeObserver = new ResizeObserver(() => {
      this.resize();
      this.draw();
    });
    this.resizeObserver.observe(this.canvas);
    this.resize();
    this.draw();

    this.intersectionObserver = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        this.start();
      } else {
        this.stop();
      }
    });
    this.intersectionObserver.observe(this.canvas);

    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.draw();
    });
  },

  destroyed() {
    this.stop();
    for (const card of this.cards || []) {
      card.removeEventListener("mouseenter", this.onCardEnter);
      card.removeEventListener("mouseleave", this.onCardLeave);
    }
    this.offThemeChange?.();
    this.resizeObserver?.disconnect();
    this.intersectionObserver?.disconnect();
  },

  resolveColors() {
    for (const series of this.series) {
      series.stroke = resolveColor(this.host, `--insights-${series.name}-stroke`);
      series.highlight = resolveColor(this.host, `--insights-${series.name}-highlight`);
    }
  },

  setHighlight(name) {
    for (const series of this.series) {
      series.glowTarget = series.name === name ? 1 : 0;
      // With the loop paused (reduced motion) there is no frame to ease
      // through, so snap and repaint.
      if (this.reduceMotion) series.glow = series.glowTarget;
    }
    if (this.reduceMotion) this.draw();
  },

  resize() {
    const dpr = window.devicePixelRatio || 1;
    const rect = this.canvas.getBoundingClientRect();
    this.width = rect.width;
    this.height = rect.height;
    const w = Math.round(rect.width * dpr);
    const h = Math.round(rect.height * dpr);
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.resolveColors();
    this.fillBuffers();
  },

  // Keep every series holding enough segments to reach past the left edge
  // by at least one full step beyond the current scroll offset, so the
  // entering step is always fully formed off-screen — it never grows into
  // view pixel by pixel. Called on resize and after every shift, since a
  // shift swaps a segment for one of a different random width.
  fillBuffers() {
    for (const series of this.series) {
      this.fillBuffer(series);
    }
  },

  fillBuffer(series) {
    const needed = this.width + series.offset + 2 * SEGMENT_MAX_WIDTH * this.width;
    while (series.total < needed) {
      const segment = this.nextSegment(series);
      series.segments.push(segment);
      series.total += segment.width;
    }
  },

  nextSegment(series) {
    const last = series.segments[series.segments.length - 1];
    const prev = last ? last.value : between(series.lo, series.hi);
    const jump = (series.hi - series.lo) * MAX_STEP;
    const value = Math.min(series.hi, Math.max(series.lo, prev + between(-jump, jump)));
    return { width: this.width * between(SEGMENT_MIN_WIDTH, SEGMENT_MAX_WIDTH), value };
  },

  start() {
    if (this.frame || this.reduceMotion) return;
    this.lastTime = null;
    const tick = (time) => {
      this.frame = requestAnimationFrame(tick);
      const dt = this.lastTime ? Math.min((time - this.lastTime) / 1000, 0.1) : 0;
      this.lastTime = time;
      this.update(dt);
      this.draw();
    };
    this.frame = requestAnimationFrame(tick);
  },

  stop() {
    if (this.frame) {
      cancelAnimationFrame(this.frame);
      this.frame = null;
    }
  },

  update(dt) {
    const travel = SCROLL_SPEED * this.width * dt;
    const ease = Math.min(1, dt * HIGHLIGHT_EASE);
    for (const series of this.series) {
      series.glow += (series.glowTarget - series.glow) * ease;
      series.offset += travel;
      // The oldest segment sits at the right edge; once it has scrolled
      // fully off, drop it and grow a fresh step to enter on the left.
      while (series.segments.length && series.offset >= series.segments[0].width) {
        series.offset -= series.segments[0].width;
        series.total -= series.segments[0].width;
        series.segments.shift();
      }
      this.fillBuffer(series);
    }
  },

  draw() {
    const ctx = this.ctx;
    const { width, height } = this;
    if (!width || !height) return;
    const scale = height - TOP_MARGIN - BOTTOM_MARGIN;
    const baseline = height - BOTTOM_MARGIN;

    ctx.clearRect(0, 0, width, height);
    ctx.lineWidth = LINE_WIDTH;
    ctx.lineJoin = "round";
    ctx.lineCap = "round";

    // A highlighted series paints last so it sits on top of the others.
    const order = [...this.series].sort((a, b) => a.glow - b.glow);
    for (const series of order) {
      // Segments are stored oldest first; the oldest is furthest right, so
      // walk from the right edge back toward the left, with the newest
      // (partially entered) step hanging off the left edge.
      let x = width + series.offset;
      ctx.beginPath();
      let first = true;
      for (const segment of series.segments) {
        const to = x;
        const from = x - segment.width;
        const y = baseline - segment.value * scale;
        if (first) {
          ctx.moveTo(to, y);
          first = false;
        } else {
          ctx.lineTo(to, y);
        }
        ctx.lineTo(from, y);
        x = from;
        if (from < 0) break;
      }
      // Base stroke, then the highlight colour faded in over it.
      ctx.strokeStyle = series.stroke;
      ctx.stroke();
      if (series.glow > 0.01) {
        ctx.globalAlpha = series.glow;
        ctx.strokeStyle = series.highlight;
        ctx.stroke();
        ctx.globalAlpha = 1;
      }
    }
  },
};

export { InsightsChart };
