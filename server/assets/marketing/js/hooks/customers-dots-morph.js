import { whenInView } from "../lib/in-view.js";
import { onThemeChange } from "../lib/theme.js";

/*
 * Dot field along the bottom of the home customers carousel card. Each
 * customer story has its own chart, drawn in 2px dots on a 4px grid with
 * ordered (Bayer) dither for density, that hints at the result in the copy:
 *
 *   bars       — 3D-shaded columns stepping down (Monzo's CI time, -71%)
 *   histogram  — build durations: ghosted columns where the old builds sat
 *                and solid columns now piled up at the fast end (Toss:
 *                builds finishing within a minute more than tripled)
 *   fall       — a line falling below a dashed "before" level, with a
 *                dither gradient under it (Trendyol's build times, -65%)
 *   steps      — the same, stepping down in stages (monday.com's CI)
 *   pairs      — ghosted tall "before" columns beside short solid "after"
 *                ones (Delivery Hero's clean builds, 2.5 → 0.5 min)
 *   rise       — a rising line with a dither gradient under it (a quote
 *                without a single metric, such as OpenAI's)
 *
 * A dotted baseline stays put as the chart's frame.
 *
 * When the carousel changes slide it dispatches "customers:figure" with the
 * next chart's name. The dots then morph the way the reference (Stripe's
 * stats section) does, with depth: they leave the chart and gather into a
 * loose, slowly folding blob of nested dotted shells, brightest at its rim
 * and dark in the middle with a little spray drifting off it (drawn in
 * perspective on a tilted spin), hover there for a moment, then burst out
 * to the new chart, each trailing a few fading dots.
 * At rest every dot breathes gently on its own phase.
 *
 * Charts are generated for the canvas width (a fixed 216px tall) from a
 * seeded RNG, so they are stable across loads. Drawing goes straight into
 * an ImageData buffer, which keeps a few thousand dots cheap per frame.
 * Under prefers-reduced-motion charts swap instantly and nothing animates.
 */

const HEIGHT = 216; // keep in sync with the card's dot band in home.css
const CELL = 4; // grid pitch, CSS px
const ROWS = HEIGHT / CELL; // 54
const PLOT_TOP = 3;
const PLOT_BOTTOM = ROWS - 3; // the baseline sits just below it

const GATHER_MS = 360;
const HOVER_MS = 650;
const BURST_MS = 380;
const GATHER_STAGGER_MS = 140;
const BURST_STAGGER_MS = 120;
const TRAIL = [0.05, 0.1, 0.16];
const TRAIL_ALPHA = [0.5, 0.3, 0.14];
const FLICKER_MS = 6000;
// At rest only the slow breathing changes, so the field repaints at a third
// of the display rate; a morph repaints every frame.
const REST_FRAME_SKIP = 3;
const TAU = Math.PI * 2;

const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const bayer = (cx, cy) => (BAYER4[(cy & 3) * 4 + (cx & 3)] + 0.5) / 16;

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function seedOf(text) {
  let h = 2166136261;
  for (const ch of text) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  return h >>> 0;
}

const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const easeOut = (t) => 1 - Math.pow(1 - t, 3);
const clamp01 = (t) => (t < 0 ? 0 : t > 1 ? 1 : t);
const rowOf = (v) => Math.round(PLOT_BOTTOM - clamp01(v) * (PLOT_BOTTOM - PLOT_TOP));

// A chart under construction: one dot per occupied cell, brightest wins.
function canvasOf(cols) {
  const cells = new Map();
  return {
    cols,
    plot(cx, cy, density, tone) {
      if (cx < 0 || cx >= cols || cy < 0 || cy >= ROWS) return;
      if (density <= bayer(cx, cy)) return;
      const key = cy * cols + cx;
      const prev = cells.get(key);
      if (!prev || prev.tone < tone) cells.set(key, { x: cx * CELL + 1, y: cy * CELL + 1, tone });
    },
    dots: () => Array.from(cells.values()),
  };
}

// A column `width` cells wide from the baseline up to value `v`: a lit cap,
// a body that thins with depth, and a dimmer right-hand face for depth.
// Ghost columns are a faint body inside a dotted outline.
function column(c, cx, width, v, { body = 0.62, fade = 0.42, tone = 0.7, ghost = false } = {}) {
  const top = rowOf(v);
  const height = Math.max(1, PLOT_BOTTOM - top);
  for (let x = cx; x < cx + width; x++) {
    const side = x === cx + width - 1 && width > 1 ? 0.55 : 1;
    c.plot(x, top, ghost ? 0.9 : 1, ghost ? 0.42 : 1);
    for (let y = top + 1; y <= PLOT_BOTTOM; y++) {
      const depth = (y - top) / height;
      const edge = ghost && (x === cx || x === cx + width - 1) ? 0.55 : 0;
      c.plot(x, y, Math.max((body - fade * depth) * side, edge), ghost ? 0.32 : tone * side + 0.15);
    }
  }
}

// A line through `level(u)` with a lit core, a soft glow either side and an
// ordered-dither gradient underneath that fades to the baseline.
function lineChart(c, level, { before = null } = {}) {
  let prev = null;
  for (let cx = 0; cx < c.cols; cx++) {
    const row = rowOf(level(cx / c.cols));
    // Join vertical jumps (step edges) with a lit riser.
    if (prev !== null && Math.abs(row - prev) > 1) {
      for (let y = Math.min(row, prev); y <= Math.max(row, prev); y++) c.plot(cx, y, 1, 0.9);
    }
    prev = row;
    c.plot(cx, row, 1, 1);
    c.plot(cx, row - 1, 0.5, 0.75);
    c.plot(cx, row + 1, 0.62, 0.8);
    const span = Math.max(1, PLOT_BOTTOM - row - 1);
    for (let y = row + 2; y <= PLOT_BOTTOM; y++) {
      const depth = (y - row - 2) / span;
      c.plot(cx, y, 0.5 * Math.pow(1 - depth, 1.4), 0.55);
    }
    // The "before" level as a dashed line, so the change reads at a glance.
    if (before !== null && cx % 4 < 2) c.plot(cx, rowOf(before), 1, 0.4);
  }
}

const FIGURES = {
  bars: (rng, cols) => {
    const c = canvasOf(cols);
    for (let cx = 1; cx < cols - 3; cx += 4) {
      const u = cx / cols;
      column(c, cx, 3, (0.92 - 0.62 * u) * (0.84 + 0.16 * rng()));
    }
    return c.dots();
  },
  histogram: (rng, cols) => {
    const c = canvasOf(cols);
    // Build durations, fast on the left. Each bucket overlays a ghosted
    // "before" column (the old spread, centred on slower builds) and a solid
    // "after" column (builds now piled up at the fast end); where after
    // rises above before it covers it, elsewhere the ghost shows the shift.
    for (let cx = 1; cx < cols - 3; cx += 4) {
      const u = cx / cols;
      const jitter = 0.92 + 0.08 * rng();
      const before = (0.06 + 0.6 * Math.exp(-Math.pow((u - 0.52) / 0.24, 2))) * jitter;
      const after = (0.05 + 0.86 * Math.exp(-Math.pow((u - 0.13) / 0.15, 2))) * jitter;
      column(c, cx, 3, before, { ghost: true, body: 0.2, fade: 0.08 });
      column(c, cx, 3, after, { body: 0.72, fade: 0.38, tone: 0.8 });
    }
    return c.dots();
  },
  fall: (rng, cols) => {
    const c = canvasOf(cols);
    const wobble = rng() * TAU;
    lineChart(c, (u) => 0.82 - 0.55 * easeInOut(clamp01((u - 0.12) / 0.76)) + 0.025 * Math.sin(u * 21 + wobble), {
      before: 0.82,
    });
    return c.dots();
  },
  steps: (rng, cols) => {
    const c = canvasOf(cols);
    const stops = [
      [0.2, 0.84],
      [0.4, 0.7],
      [0.6, 0.57],
      [0.8, 0.46],
      [1, 0.38],
    ];
    lineChart(
      c,
      (u) => {
        for (const [end, value] of stops) if (u <= end) return value;
        return stops[stops.length - 1][1];
      },
      { before: 0.84 },
    );
    return c.dots();
  },
  pairs: (rng, cols) => {
    const c = canvasOf(cols);
    for (let cx = 1; cx < cols - 9; cx += 12) {
      const before = 0.82 + 0.12 * rng();
      column(c, cx, 4, before, { ghost: true, body: 0.22, fade: 0.08 });
      column(c, cx + 5, 4, before * 0.2, { body: 0.9, fade: 0.2, tone: 0.85 });
    }
    return c.dots();
  },
  rise: (rng, cols) => {
    const c = canvasOf(cols);
    const wobble = rng() * TAU;
    lineChart(c, (u) => 0.22 + 0.6 * easeInOut(clamp01((u - 0.08) / 0.84)) + 0.025 * Math.sin(u * 19 + wobble));
    return c.dots();
  },
};

// The chart frame: a dotted baseline.
function frameDots(cols) {
  const dots = [];
  for (let cx = 0; cx < cols; cx += 2) dots.push({ x: cx * CELL + 1, y: (PLOT_BOTTOM + 1) * CELL + 1, tone: 0.42 });
  return dots;
}

function resolveColor(host, name) {
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
  const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
  return { r, g, b, alpha: a / 255 };
}

export const CustomersDotsMorph = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.parentElement;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.figure = this.el.dataset.figure || "bars";
    this.particles = [];
    this.morph = null;
    this.w = 0;
    this.raf = 0;
    this.running = false;

    this.resolveColors = () => {
      this.ink = resolveColor(this.host, "--home-customers-dots-ink");
    };
    this.resolveColors();
    this.offTheme = onThemeChange(() => {
      this.resolveColors();
      this.render(performance.now());
    });

    this.onFigure = (event) => this.morphTo(event.detail?.figure);
    this.el.addEventListener("customers:figure", this.onFigure);

    this.resize = () => {
      const rect = this.canvas.getBoundingClientRect();
      this.dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = Math.max(1, Math.round(rect.width));
      this.canvas.width = Math.round(w * this.dpr);
      this.canvas.height = Math.round(HEIGHT * this.dpr);
      this.image = this.ctx.createImageData(this.canvas.width, this.canvas.height);
      this.pixels = new Uint32Array(this.image.data.buffer);
      if (w !== this.w) {
        this.w = w;
        this.layout();
      }
      this.render(performance.now());
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.canvas);
    this.resize();

    let tick = 0;
    const loop = (now) => {
      this.raf = requestAnimationFrame(loop);
      if (this.morph || tick++ % REST_FRAME_SKIP === 0) this.render(now);
    };
    this.stopView = whenInView(this.el, {
      enter: () => {
        if (this.reduced || this.running) return;
        this.running = true;
        this.raf = requestAnimationFrame(loop);
      },
      leave: () => {
        this.running = false;
        cancelAnimationFrame(this.raf);
      },
    });
  },

  destroyed() {
    cancelAnimationFrame(this.raf);
    this.observer?.disconnect();
    this.stopView?.();
    this.offTheme?.();
    this.el.removeEventListener("customers:figure", this.onFigure);
  },

  // Generates every chart for the current width and sizes the particle pool
  // to the largest; a chart with fewer dots parks the spare particles,
  // invisible, on its own dots. Resizing snaps to the current chart.
  layout() {
    const cols = Math.floor(this.w / CELL);
    this.frame = frameDots(cols);
    this.figures = {};
    let count = 0;
    for (const [name, make] of Object.entries(FIGURES)) {
      const rng = mulberry32(seedOf(name));
      const dots = make(rng, cols);
      // Deterministic shuffle so particles fly to scattered new places
      // rather than sliding sideways in order.
      for (let i = dots.length - 1; i > 0; i--) {
        const j = Math.floor(rng() * (i + 1));
        [dots[i], dots[j]] = [dots[j], dots[i]];
      }
      this.figures[name] = dots;
      count = Math.max(count, dots.length);
    }
    const rng = mulberry32(seedOf("particles"));
    this.particles = Array.from({ length: count }, (_, i) => {
      // Each particle's home in the transition form: a random direction
      // (no even grid, so it never reads as a perfect sphere) on one of
      // three nested shells that fold independently, or, for a few, loose
      // spray drifting outside the body.
      const gauss = () => rng() + rng() + rng() - 1.5;
      let dx = gauss();
      let dy = gauss();
      let dz = gauss();
      const length = Math.hypot(dx, dy, dz) || 1;
      dx /= length;
      dy /= length;
      dz /= length;
      const spray = rng() < 0.08;
      return {
        index: i,
        phase: rng() * TAU,
        gatherDelay: rng() * GATHER_STAGGER_MS,
        burstDelay: rng() * BURST_STAGGER_MS,
        dir: { x: dx, y: dy, z: dz },
        shell: Math.floor(rng() * 3),
        spray,
        sprayRadius: 1.06 + 0.32 * rng() * rng(),
      };
    });
    this.morph = null;
    this.assign(this.figure, "at");
  },

  // Points every particle's `key` ("at" or "to") at its dot in `figure`.
  assign(figure, key) {
    const dots = this.figures[figure] || this.figures.bars;
    for (const p of this.particles) {
      const dot = dots[p.index % dots.length];
      p[key] = { x: dot.x, y: dot.y, tone: dot.tone, visible: p.index < dots.length };
    }
  },

  morphTo(figure) {
    if (!figure || !this.figures?.[figure] || figure === this.figure) return;
    this.figure = figure;
    if (this.reduced) {
      this.assign(figure, "at");
      this.render(performance.now());
      return;
    }
    // Start from wherever each dot is now, mid-morph included.
    const now = performance.now();
    for (const p of this.particles) {
      const pos = this.position(p, now);
      p.from = { x: pos.x, y: pos.y, tone: pos.tone * pos.alpha, visible: pos.visible };
    }
    this.assign(figure, "to");
    this.morph = { start: now };
  },

  // The particle's place in the transition form at `now`, projected with
  // perspective. The form is a loose, living blob rather than a sphere:
  // each shell's radius is pushed in and out by a slowly drifting noise
  // field, so the surface folds and ripples, and dots crowd brightest where
  // the surface turns edge-on (the rim) while the middle stays dark and
  // sparse. Returns screen position, a tone and a dot size.
  cloudPoint(p, now) {
    const t = now / 1000;
    const { x: dx, y: dy, z: dz } = p.dir;
    // The spin and tilt are the same for every particle in a frame.
    if (this.trigAt !== now) {
      const spin = t * 0.45;
      const tilt = 0.38;
      this.trig = { cs: Math.cos(spin), ss: Math.sin(spin), ct: Math.cos(tilt), st: Math.sin(tilt) };
      this.trigAt = now;
    }
    const { cs, ss, ct, st } = this.trig;
    const k = p.shell * 2.1;
    const fold =
      Math.sin(dx * 2.6 + t * 0.9 + k) * Math.sin(dy * 3.1 - t * 0.7 + k * 0.5) +
      0.6 * Math.sin(dz * 3.4 + dx * 1.8 + t * 0.55 - k) +
      0.35 * Math.sin((dx + dy - dz) * 5.2 + t * 1.3 + k);
    const radius = p.spray ? p.sprayRadius : (1 - p.shell * 0.06) * (1 + 0.12 * fold);

    // Spin around the vertical axis, then tilt toward the viewer.
    const rot = (x, y, z) => {
      const x1 = x * cs + z * ss;
      const z1 = -x * ss + z * cs;
      return [x1, y * ct - z1 * st, y * st + z1 * ct];
    };
    const [x, y, z] = rot(dx * radius, dy * radius, dz * radius);
    // How edge-on the surface is to the viewer here: 1 at the rim.
    const facing = Math.abs(rot(dx, dy, dz)[2]);
    const rim = Math.pow(1 - facing, 1.6);
    const near = clamp01((1 - z) / 2);

    const scale = HEIGHT * 0.36;
    const perspective = 1 / (1 + z * 0.22);
    const tone = p.spray ? 0.25 + 0.35 * near : (0.14 + 0.86 * rim) * (0.6 + 0.4 * near);
    return {
      x: this.w / 2 + x * scale * 1.08 * perspective,
      y: HEIGHT * 0.5 + y * scale * perspective,
      tone,
      size: !p.spray && rim > 0.55 && near > 0.35 ? 2 : 1,
    };
  },

  // Where a particle is at `now`, with tone, size and opacity, plus how far
  // it is through the burst (for trails).
  position(p, now) {
    if (!this.morph) return { ...p.at, size: 2, alpha: 1, burst: 1 };
    const t = now - this.morph.start;
    const hoverEnd = GATHER_MS + GATHER_STAGGER_MS + HOVER_MS;
    if (t < hoverEnd + p.burstDelay) {
      const cloud = this.cloudPoint(p, now);
      const g = easeInOut(clamp01((t - p.gatherDelay) / GATHER_MS));
      return {
        x: p.from.x + (cloud.x - p.from.x) * g,
        y: p.from.y + (cloud.y - p.from.y) * g,
        tone: p.from.tone + (cloud.tone - p.from.tone) * g,
        size: g > 0.5 ? cloud.size : 2,
        visible: true,
        alpha: p.from.visible ? 1 : g,
        burst: 0,
      };
    }
    // Fly out from where the particle was in the blob when its burst began.
    const origin = this.cloudPoint(p, this.morph.start + hoverEnd + p.burstDelay);
    const burst = clamp01((t - hoverEnd - p.burstDelay) / BURST_MS);
    const e = easeOut(burst);
    return {
      x: origin.x + (p.to.x - origin.x) * e,
      y: origin.y + (p.to.y - origin.y) * e,
      tone: origin.tone + (p.to.tone - origin.tone) * e,
      size: burst < 0.6 ? origin.size : 2,
      visible: true,
      alpha: p.to.visible ? 1 : 1 - burst,
      burst,
      origin,
    };
  },

  // A square dot into the pixel buffer, keeping the brighter of overlaps.
  dot(x, y, size, alpha) {
    if (alpha <= 0.01) return;
    const dpr = this.dpr;
    const width = this.canvas.width;
    const height = this.canvas.height;
    const a = Math.min(255, Math.round(alpha * 255));
    const color = ((a << 24) | (this.ink.b << 16) | (this.ink.g << 8) | this.ink.r) >>> 0;
    const x0 = Math.round(x * dpr);
    const y0 = Math.round(y * dpr);
    const span = Math.max(1, Math.round(size * dpr));
    for (let py = Math.max(0, y0); py < Math.min(height, y0 + span); py++) {
      const row = py * width;
      for (let px = Math.max(0, x0); px < Math.min(width, x0 + span); px++) {
        if (this.pixels[row + px] >>> 24 < a) this.pixels[row + px] = color;
      }
    }
  },

  render(now) {
    if (!this.ctx || !this.w || !this.pixels) return;
    this.pixels.fill(0);
    const base = this.ink.alpha || 1;
    for (const d of this.frame) this.dot(d.x, d.y, 2, d.tone * base);

    let done = true;
    for (const p of this.particles) {
      const pos = this.position(p, now);
      if (this.morph && pos.burst < 1) done = false;
      if (!pos.visible) continue;
      const breathe = this.reduced ? 1 : 0.82 + 0.18 * Math.sin((now / FLICKER_MS) * TAU + p.phase);
      const alpha = base * pos.tone * breathe * pos.alpha;
      this.dot(pos.x, pos.y, pos.size, alpha);
      // Trails while bursting out: fading dots a little way back along the
      // path, so each flight reads as a dotted stroke.
      if (pos.origin && pos.burst > 0 && pos.burst < 1) {
        for (let k = 0; k < TRAIL.length; k++) {
          const back = easeOut(clamp01(pos.burst - TRAIL[k]));
          this.dot(
            pos.origin.x + (p.to.x - pos.origin.x) * back,
            pos.origin.y + (p.to.y - pos.origin.y) * back,
            1,
            alpha * TRAIL_ALPHA[k],
          );
        }
      }
    }
    this.ctx.putImageData(this.image, 0, 0);

    if (this.morph && done && now - this.morph.start > GATHER_MS + HOVER_MS) {
      for (const p of this.particles) p.at = p.to;
      this.morph = null;
    }
  },
};
