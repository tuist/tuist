// Animated build-time comparison chart for the home "Cache" feature section.
//
// One continuous step time-series scrolls left to right across the whole
// canvas. Steps are born on the left following a seismograph-style walk —
// climbing, pulling back, climbing again. Each step crosses the center
// divider at its full height (the red trace continues seamlessly into the
// purple half), holds for a while, then eases down to a low tail — cache
// kicking in. The two halves are the same trace drawn with different
// colors, split at the divider.
//
// Perf notes: the step buffer and clip strings are reused across frames
// (no per-frame allocations beyond a few numbers), and each half's path is
// built only from the steps inside it, with coordinates clamped instead of
// ctx.clip().
import { onThemeChange } from "../lib/theme.js";

const FALLBACK_COLORS = {
  withoutStroke: "#e5484d",
  withoutFill: "#fdeeec",
  withStroke: "#8253ff",
  withFill: "#f4f4ff",
};

const TOP_MARGIN = 12;

// Classic 8×8 ordered Bayer matrix, 2px cells — the site's unified dither.
const BAYER8 = [
  0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54,
  22, 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29,
  53, 21,
];
const DITHER_PITCH = 2;
const DITHER_TILE = DITHER_PITCH * 8;

// Series geometry, in fractions of the half width. The visible canvas spans
// 2 half-widths; the buffer holds a bit more so a partial segment is always
// ready to enter on the left.
const SCROLL_SPEED = 0.06;
const SEGMENT_MIN_WIDTH = 0.025;
const SEGMENT_MAX_WIDTH = 0.05;
const BUFFER_SPAN = 2.5;

// Walk band for freshly born steps (the "without cache" look).
const WALK_MIN = 0.35;
const WALK_MAX = 0.95;

// Once fully past the divider (plus a hold distance, so the purple step
// carries on for a while first), steps ease toward their low target.
const HOLD_DISTANCE = 0.2;
const LOW_MIN = 0.05;
const LOW_MAX = 0.16;
const DECAY_RATE = 1.4;

// Stat counters are driven live off the graph: each samples the trace
// height at a point (sampleX in half-width units — <1 is the red half, >1
// the purple half), normalizes it against that half's band [lo, hi], and
// maps it into a value range. Higher trace → longer build (invert flips it,
// so a lower purple trace reads as a higher cache-hit ratio).
//
// The build-time ranges span the kind of numbers big projects actually see
// (~30–50 min without cache, dropping anywhere from a few minutes down to
// seconds with cache) and are chosen so the derived "savings" badge —
// (slow − fast) / slow, computed live off the two displayed build times —
// lands in the 80–99% band regardless of how the two traces line up:
//   worst case (fast hi / slow lo)  = 300 / 1800 = 0.167 → 83%
//   best  case (fast lo / slow hi)  =  30 / 3000 = 0.010 → 99%
const COUNTER_SOURCES = {
  // Sampled at the entry edge (left) so the number tracks the step as it
  // enters the red area, with a faster ease so it matches on entry rather
  // than lagging a step behind.
  "build-slow": { sampleX: 0.05, lo: WALK_MIN, hi: WALK_MAX, min: 1800, max: 3000, ease: 6 },
  "build-fast": { sampleX: 1.5, lo: LOW_MIN, hi: 0.45, min: 30, max: 300 },
  "hit-fast": { sampleX: 1.5, lo: LOW_MIN, hi: 0.45, min: 86, max: 98, invert: true },
  // Derived from the live build-slow/build-fast displays, not the trace.
  savings: { derived: true, min: 80, max: 99 },
};
const COUNTER_EASE = 2.2;
const COUNTER_WRITE_MS = 90;

export const CacheChart = {
  mounted() {
    // The hook lives on the illustration wrapper and drives one continuous
    // trace across two canvases — the "without cache" (red) and "with cache"
    // (purple) halves. Side by side on desktop they read as one chart split
    // by a divider; stacked on mobile they become two paired mini-charts.
    this.canvasWithout = this.el.querySelector('[data-half="without"]');
    this.canvasWith = this.el.querySelector('[data-half="with"]');
    this.ctxWithout = this.canvasWithout.getContext("2d");
    this.ctxWith = this.canvasWith.getContext("2d");
    this.frame = null;
    this.lastTime = null;
    this.steps = [];
    this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    this.series = this.buildSeries();

    // Stat counters above each chart — driven live off the graph so they
    // wander to match the trace. Each starts at 0 (a count-up on first
    // reveal) and eases toward its sampled target every frame.
    this.counters = Array.from(this.el.querySelectorAll("[data-count-format]")).map((el) => ({
      el,
      format: el.dataset.countFormat,
      source: COUNTER_SOURCES[el.dataset.countSource] || null,
      display: 0,
      lastText: "",
      lastWrite: 0,
    }));

    // Keyed lookup so the derived "savings" counter can read the live
    // build-slow/build-fast displays each frame. build-slow and build-fast
    // precede the badge in DOM order, so they're eased first this frame.
    this.countersBySource = {};
    for (const counter of this.counters) {
      const name = counter.el.dataset.countSource;
      if (name) this.countersBySource[name] = counter;
    }

    this.resizeObserver = new ResizeObserver(() => {
      this.resize();
      // Always redraw synchronously: resize() wipes the backing store, so
      // deferring the repaint to the next animation frame leaves a blank
      // canvas in between — a visible flash on every observer tick while the
      // window is being dragged.
      this.draw();
    });
    this.resizeObserver.observe(this.canvasWithout);
    this.resizeObserver.observe(this.canvasWith);
    this.resize();
    this.draw();

    this.intersectionObserver = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        this.start();
      } else {
        this.stop();
      }
    });
    this.intersectionObserver.observe(this.el);

    // resize() re-reads the theme-resolved CSS colors; repaint with them on
    // a runtime scheme flip.
    this.offThemeChange = onThemeChange(() => {
      this.resize();
      this.draw();
    });
  },

  destroyed() {
    this.stop();
    this.offThemeChange?.();
    this.resizeObserver?.disconnect();
    this.intersectionObserver?.disconnect();
  },

  formatCount(value, format) {
    const n = Math.round(value);
    if (format === "percent") return `${n}%`;
    if (format === "time") {
      // Always render mm:ss with both fields zero-padded so the string length
      // (and thus the centered row's width) stays constant as the value ticks
      // — otherwise a sub-minute value ("12s") and a multi-minute one
      // ("5m 00s") have different widths and shift the layout.
      const pad = (s) => String(s).padStart(2, "0");
      return `${pad(Math.floor(n / 60))}m ${pad(n % 60)}s`;
    }
    return String(n);
  },

  // Sample the trace height at sampleX (in half-width units) from the steps
  // built this frame.
  sampleTrace(sampleX) {
    const steps = this.steps;
    if (!steps.length) return 0.5;
    const x = sampleX * this.canvasHalf;
    for (const step of steps) {
      if (x >= step.from && x < step.to) return step.value;
    }
    return steps[steps.length - 1].value;
  },

  // Drive each stat live off the graph: ease the display toward the sampled
  // target and rewrite the DOM only when the formatted value changes (and
  // no more than every COUNTER_WRITE_MS, so fast-ticking digits stay legible).
  updateCounters(dt, now) {
    if (this.counters.length === 0) return;

    for (const counter of this.counters) {
      let target = 0;
      const src = counter.source;
      const ease = Math.min(1, dt * (src?.ease || COUNTER_EASE));
      if (src?.derived) {
        // Live cache savings: (without − with) / without, straight off the
        // two displayed build times. Ranges keep it inside [min, max]; the
        // clamp only guards rounding at the edges.
        const slow = this.countersBySource["build-slow"]?.display || 0;
        const fast = this.countersBySource["build-fast"]?.display || 0;
        const savings = slow > 0 ? (1 - fast / slow) * 100 : src.min;
        target = Math.min(src.max, Math.max(src.min, savings));
      } else if (src) {
        const raw = this.sampleTrace(src.sampleX);
        const norm = Math.min(1, Math.max(0, (raw - src.lo) / (src.hi - src.lo)));
        target = src.invert ? src.max - norm * (src.max - src.min) : src.min + norm * (src.max - src.min);
      }
      counter.display += (target - counter.display) * ease;

      const text = this.formatCount(counter.display, counter.format);
      if (text !== counter.lastText && now - counter.lastWrite >= COUNTER_WRITE_MS) {
        counter.lastText = text;
        counter.lastWrite = now;
        counter.el.textContent = text;
      }
    }
  },

  segmentWidth() {
    return SEGMENT_MIN_WIDTH + Math.random() * (SEGMENT_MAX_WIDTH - SEGMENT_MIN_WIDTH);
  },

  lowTarget() {
    return LOW_MIN + Math.random() * (LOW_MAX - LOW_MIN);
  },

  // Seismograph walk: small climbs and pullbacks with the occasional big
  // swing. Mean reversion toward mid-band keeps the trace wandering instead
  // of pinning flat against the top of its range.
  nextWalkValue(series) {
    const reversion = (0.65 - series.lastValue) * 0.2;
    const roll = Math.random();
    let delta;
    if (roll < 0.12) {
      delta = (Math.random() < 0.5 ? -1 : 1) * (0.15 + Math.random() * 0.2);
    } else if (roll < 0.55) {
      delta = -(0.03 + Math.random() * 0.1);
    } else {
      delta = 0.03 + Math.random() * 0.12;
    }
    const value = Math.min(WALK_MAX, Math.max(WALK_MIN, series.lastValue + delta + reversion));
    series.lastValue = value;
    return value;
  },

  // Prefill the buffer in its settled state: walk values on the red side,
  // and past the divider the same values pre-decayed toward their low
  // targets by the distance already travelled.
  buildSeries() {
    const series = {
      segments: [],
      offset: 0,
      lastValue: 0.6 + Math.random() * 0.25,
    };

    // Oldest first: p accumulates from the exit end (p=0) toward the birth
    // end. Post-mirror, the divider sits at p=1; p<1 is the purple half.
    let p = 0;
    while (p < BUFFER_SPAN) {
      const width = this.segmentWidth();
      const walkValue = this.nextWalkValue(series);
      const target = this.lowTarget();
      let value = walkValue;
      if (p + width <= 1 - HOLD_DISTANCE) {
        const timeSinceHold = (1 - HOLD_DISTANCE - (p + width)) / SCROLL_SPEED;
        value = target + (walkValue - target) * Math.exp(-DECAY_RATE * timeSinceHold);
      }
      series.segments.push({ width, value, target });
      p += width;
    }

    return series;
  },

  resizeCanvas(canvas, ctx) {
    const dpr = window.devicePixelRatio || 1;
    const { clientWidth, clientHeight } = canvas;
    if (clientWidth === 0 || clientHeight === 0) return;
    const w = Math.round(clientWidth * dpr);
    const h = Math.round(clientHeight * dpr);
    // Writing canvas.width/height wipes the backing store even if the value
    // is unchanged, so skip it when the pixel size hasn't actually moved —
    // the observer fires once per canvas, and an unchanged wipe is a flash.
    if (canvas.width === w && canvas.height === h) return;
    canvas.width = w;
    canvas.height = h;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  },

  resize() {
    this.resizeCanvas(this.canvasWithout, this.ctxWithout);
    this.resizeCanvas(this.canvasWith, this.ctxWith);

    // Real properties carry the theme-resolved light-dark() colors, since
    // custom properties return the unresolved light-dark() string. Each
    // canvas holds its own fill/stroke on border-top/border-bottom.
    const s0 = getComputedStyle(this.canvasWithout);
    const s1 = getComputedStyle(this.canvasWith);
    this.colors = {
      withoutFill: s0.borderTopColor || FALLBACK_COLORS.withoutFill,
      withoutStroke: s0.borderBottomColor || FALLBACK_COLORS.withoutStroke,
      withFill: s1.borderTopColor || FALLBACK_COLORS.withFill,
      withStroke: s1.borderBottomColor || FALLBACK_COLORS.withStroke,
    };
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
      this.updateCounters(dt, time);
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
    const series = this.series;
    series.offset += SCROLL_SPEED * dt;
    while (series.segments.length > 0 && series.offset >= series.segments[0].width) {
      series.offset -= series.segments[0].width;
      series.segments.shift();
      series.segments.push({
        width: this.segmentWidth(),
        value: this.nextWalkValue(series),
        target: this.lowTarget(),
      });
    }

    // A step holds its walk height until it has fully crossed the divider
    // plus the hold distance, then eases down to its low target.
    const decayEase = Math.min(1, dt * DECAY_RATE);
    const decayBefore = 1 - HOLD_DISTANCE;
    let p = -series.offset;
    for (const segment of series.segments) {
      if (p + segment.width <= decayBefore) {
        segment.value += (segment.target - segment.value) * decayEase;
      }
      p += segment.width;
    }
  },

  // Mirror the series into screen space (fresh segments enter at the left
  // edge and travel rightward), reusing the step buffer across frames.
  buildSteps(half, width) {
    const segments = this.series.segments;
    const steps = this.steps;
    steps.length = segments.length;

    // segments[0] is the oldest, which mirrors to the rightmost position on
    // screen — so it fills the steps buffer from the end, keeping the steps
    // in ascending x order.
    let edge = -this.series.offset * half;
    for (let i = 0; i < segments.length; i++) {
      const to = edge + segments[i].width * half;
      const j = segments.length - 1 - i;
      const step = steps[j] || (steps[j] = {});
      step.from = width - to;
      step.to = width - edge;
      step.value = segments[i].value;
      edge = to;
    }

    return steps;
  },

  draw() {
    // Both halves are the same width (equal desktop columns / equal stacked
    // rows), so one canvas width is the "half" and the full trace spans two.
    const half = this.canvasWithout.clientWidth;
    if (half === 0) return;
    this.canvasHalf = half;
    const width = half * 2;
    const steps = this.buildSteps(half, width);

    // Without-cache (red) canvas covers screen x [0, half]; with-cache
    // (purple) canvas covers [half, width], drawn shifted left by `half`
    // into its own local space. A step straddling the seam keeps one height,
    // so the trace reads continuously across the divider on desktop.
    const h0 = this.canvasWithout.clientHeight;
    this.ctxWithout.clearRect(0, 0, half, h0);
    this.drawRegion(this.ctxWithout, steps, 0, half, 0, h0, this.colors.withoutStroke, this.colors.withoutFill);

    const h1 = this.canvasWith.clientHeight;
    this.ctxWith.clearRect(0, 0, half, h1);
    this.drawRegion(this.ctxWith, steps, half, width, half, h1, this.colors.withStroke, this.colors.withFill);
  },

  // Draw the trace within screen range [x0, x1) into `ctx`, offsetting the x
  // coordinates by `xOffset` into the target canvas's local space. Step
  // coordinates are clamped rather than clipped — cheaper than ctx.clip().
  drawRegion(ctx, steps, x0, x1, xOffset, height, stroke, fill) {
    let first = -1;
    let last = -1;
    for (let i = 0; i < steps.length; i++) {
      if (steps[i].to > x0 && steps[i].from < x1) {
        if (first === -1) first = i;
        last = i;
      }
    }
    if (first === -1) return;

    const baseline = height;
    const scale = height - TOP_MARGIN;
    const startX = Math.max(steps[first].from, x0) - xOffset;
    const endX = Math.min(steps[last].to, x1) - xOffset;

    ctx.beginPath();
    ctx.moveTo(startX, baseline);
    for (let i = first; i <= last; i++) {
      const top = baseline - steps[i].value * scale;
      ctx.lineTo(Math.max(steps[i].from, x0) - xOffset, top);
      ctx.lineTo(Math.min(steps[i].to, x1) - xOffset, top);
    }
    // Dithered gradient fill: a pre-rendered vertical density strip (dense
    // at the line, dissolving toward the baseline) tiled under each step,
    // anchored to the step's top so the gradient hangs from the trace.
    const strip = this.ditherStrip(height, stroke, fill);
    for (let i = first; i <= last; i++) {
      const top = baseline - steps[i].value * scale;
      const a = Math.max(steps[i].from, x0) - xOffset;
      const b = Math.min(steps[i].to, x1) - xOffset;
      if (b <= a || top >= baseline) continue;
      ctx.save();
      ctx.beginPath();
      ctx.rect(a, top, b - a, baseline - top);
      ctx.clip();
      const tx0 = Math.floor(a / DITHER_TILE) * DITHER_TILE;
      for (let tx = tx0; tx < b; tx += DITHER_TILE) {
        ctx.drawImage(strip, tx, top, DITHER_TILE, height);
      }
      ctx.restore();
    }

    // Stroke only the stepped top outline — the chart has no bottom or
    // side borders.
    ctx.beginPath();
    ctx.moveTo(startX, baseline - steps[first].value * scale);
    for (let i = first; i <= last; i++) {
      const top = baseline - steps[i].value * scale;
      ctx.lineTo(Math.max(steps[i].from, x0) - xOffset, top);
      ctx.lineTo(Math.min(steps[i].to, x1) - xOffset, top);
    }
    ctx.strokeStyle = stroke;
    ctx.lineWidth = 1;
    ctx.stroke();
  },

  // Lazily built (per height/color/dpr) vertical dither-gradient strip, one
  // Bayer tile wide: dense two-tone dither at the top thinning to nothing —
  // stroke-colored deep dots over fill-colored light ones.
  ditherStrip(height, stroke, fill) {
    this.strips = this.strips || {};
    const dpr = window.devicePixelRatio || 1;
    const key = `${height}|${stroke}|${fill}|${dpr}`;
    if (this.strips[key]) return this.strips[key];
    const strip = document.createElement("canvas");
    strip.width = DITHER_TILE * dpr;
    strip.height = Math.max(1, Math.ceil(height)) * dpr;
    const sctx = strip.getContext("2d");
    sctx.scale(dpr, dpr);
    const rows = Math.ceil(height / DITHER_PITCH);
    for (let cy = 0; cy < rows; cy++) {
      const n = 0.9 * Math.max(0, 1 - (cy * DITHER_PITCH) / (height * 0.85));
      for (let cx = 0; cx < 8; cx++) {
        const thr = BAYER8[(cy & 7) * 8 + (cx & 7)] / 64;
        if (thr >= n) continue;
        const shifted = BAYER8[((cy + 4) & 7) * 8 + ((cx + 4) & 7)] / 64;
        if (shifted < n * 0.7) {
          // Stroke color at low alpha composites to a light tint — keeps the
          // gradient's depth without introducing darker shades.
          sctx.globalAlpha = 0.24;
          sctx.fillStyle = stroke;
        } else {
          sctx.globalAlpha = 1;
          sctx.fillStyle = fill;
        }
        sctx.fillRect(cx * DITHER_PITCH, cy * DITHER_PITCH, DITHER_PITCH, DITHER_PITCH);
      }
    }
    this.strips[key] = strip;
    return strip;
  },
};
