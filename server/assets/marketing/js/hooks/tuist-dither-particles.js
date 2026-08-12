/*
 * Community grid — the Tuist burst as pre-dithered particles.
 *
 * The artwork is a Figma bayer-dither export (~24k run-merged particles in
 * four mono shades, 570×570), baked at build time into a packed data module
 * (see tuist-dither-data.js) — no runtime fetch or SVG parsing. The hook
 * decodes the runs into per-shade typed arrays and reconstructs the exact
 * image on the canvas, with the shades mapped onto the noora purple ramp so
 * it matches the section's other dither treatments.
 *
 * On first scroll into view the logo materializes particle by particle,
 * top → bottom: each particle's reveal order blends its vertical position
 * with a stable hash, so the fill drifts downward while staying stochastic
 * — never a clean sweep line. The order is sorted once at mount; each tick
 * appends only the newly admitted particles to a persistent offscreen
 * layer and blits it, so the animation stays cheap no matter how many
 * particles there are.
 *
 * After the reveal, hovering scatters the particles (physics ported from
 * asmitbm/dither-tool): particles inside the cursor's influence radius are
 * pushed away with a cubic falloff, a spring pulls them back to rest,
 * friction damps the motion and a position decay caps the trail. The
 * physics loop only runs while the cursor is near or particles are still
 * settling. Static (fully drawn, no hover) under prefers-reduced-motion.
 */

import { TUIST_DITHER } from "./tuist-dither-data.js";
import { onThemeChange } from "../lib/theme.js";

// Export shades 0..3 (light → dark) onto the light end of the marketing
// illustration ramp.
const SHADE_TOKENS = [
  "--marketing-illustration-neutral-1",
  "--marketing-illustration-neutral-2",
  "--marketing-illustration-neutral-3",
  "--marketing-illustration-neutral-4",
];

const REVEAL_MS = 1600; // total reveal duration
const REVEAL_TICK_HZ = 24; // quantized appends — dithery cadence without chunk-pops
// How much of a particle's reveal order is random vs its vertical position:
// 0 = a hard top→bottom sweep, 1 = pure scatter with no direction.
const REVEAL_JITTER = 0.45;

// Hover physics (dither-tool's defaults, in artwork px where relevant).
const PHYS_RADIUS = 100; // cursor influence radius
const PHYS_PUSH = 50; // push strength
const PHYS_RETURN = 0.05; // spring return speed per frame
const PHYS_FRICTION = 0.85; // velocity damping per frame
const PHYS_DECAY = 0.8; // per-frame lerp back toward rest (trail limiter)
const PHYS_SETTLE = 0.05; // displacement/velocity below this = settled

// Stable per-particle hash (0..1) jittering a particle's reveal order.
function particleHash(x, y) {
  const s = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
  return s - Math.floor(s);
}

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

function colorBytes(cssColor) {
  const c = document.createElement("canvas");
  c.width = c.height = 1;
  const ctx = c.getContext("2d");
  ctx.fillStyle = cssColor;
  ctx.fillRect(0, 0, 1, 1);
  return ctx.getImageData(0, 0, 1, 1).data;
}

// Decode the packed runs into one flat [x, y, w] array per shade (px units;
// runs are `cell` px tall).
function decodeRuns() {
  const bin = atob(TUIST_DITHER.data);
  const cell = TUIST_DITHER.cell;
  const counts = [0, 0, 0, 0];
  const words = new Uint32Array(TUIST_DITHER.runs);
  for (let i = 0; i < words.length; i++) {
    const o = i * 4;
    words[i] =
      bin.charCodeAt(o) | (bin.charCodeAt(o + 1) << 8) | (bin.charCodeAt(o + 2) << 16) | (bin.charCodeAt(o + 3) << 24);
    counts[(words[i] >>> 27) & 3]++;
  }
  const groups = counts.map((count) => new Float32Array(count * 3));
  const cursors = [0, 0, 0, 0];
  for (let i = 0; i < words.length; i++) {
    const v = words[i];
    const shade = (v >>> 27) & 3;
    const g = groups[shade];
    let c = cursors[shade];
    g[c++] = (v & 511) * cell;
    g[c++] = ((v >>> 9) & 511) * cell;
    g[c++] = ((v >>> 18) & 511) * cell;
    cursors[shade] = c;
  }
  return groups;
}

export const TuistDitherParticles = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.parentElement;
    this.groups = decodeRuns();
    this.buildRevealOrder();
    this.colors = SHADE_TOKENS.map((token) => resolveTokenColor(this.host, token));
    // data-opacity: particle opacity, 0..1 (default 1).
    const opacity = Number(this.el.dataset.opacity);
    this.opacity = Number.isFinite(opacity) ? opacity : 1;
    this.buildBackdrop();
    // Repaint with fresh token colors on a runtime scheme flip: rebuild the
    // backdrop, then resize() rebuilds the particle layer from scratch up to
    // the current reveal cut.
    this.offThemeChange = onThemeChange(() => {
      this.colors = SHADE_TOKENS.map((token) => resolveTokenColor(this.host, token));
      this.buildBackdrop();
      this.resize();
    });

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.progress = reduced ? 1 : 0;
    this.raf = null;
    this.physRaf = null;
    this.mouse = null;
    if (!reduced) {
      this.io = new IntersectionObserver(
        (entries) => {
          if (entries.some((e) => e.isIntersecting)) {
            this.startReveal();
            this.io.disconnect();
            this.io = null;
          }
        },
        { threshold: 0.35 },
      );
      this.io.observe(this.host);

      // The logo's own span is pointer-events: none, so the cursor is
      // tracked on the surrounding grid and mapped into artwork space.
      this.gridEl = this.host.closest('[data-part="community-grid"]') || this.host;
      this.onMove = (e) => {
        const rect = this.canvas.getBoundingClientRect();
        if (!rect.width) return;
        const s = TUIST_DITHER.width / rect.width;
        this.mouse = { x: (e.clientX - rect.left) * s, y: (e.clientY - rect.top) * s };
        this.startPhysics();
      };
      this.onLeave = () => {
        this.mouse = null;
      };
      this.gridEl.addEventListener("mousemove", this.onMove);
      this.gridEl.addEventListener("mouseleave", this.onLeave);
    }

    this.resize = () => {
      // Measure the canvas itself: it may be larger than its cropping
      // parent (the artwork overflows the span and gets clipped).
      const rect = this.canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      this.width = Math.max(1, Math.round(rect.width));
      this.height = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.width * dpr;
      this.canvas.height = this.height * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      // Fresh particle layer at the new size; repainted up to the current
      // reveal cut by the draw() below.
      this.layer = document.createElement("canvas");
      this.layer.width = this.canvas.width;
      this.layer.height = this.canvas.height;
      this.layerCtx = this.layer.getContext("2d");
      this.layerCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
      for (const g of this.reveal) g.drawn = 0;
      this.draw();
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.canvas);
    this.resize();
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.observer) this.observer.disconnect();
    if (this.io) this.io.disconnect();
    if (this.raf !== null) cancelAnimationFrame(this.raf);
    if (this.physRaf !== null) cancelAnimationFrame(this.physRaf);
    if (this.gridEl) {
      this.gridEl.removeEventListener("mousemove", this.onMove);
      this.gridEl.removeEventListener("mouseleave", this.onLeave);
    }
  },

  // Precompute the reveal: per shade, sort the runs by their admission key
  // (vertical position blended with hash) and keep the sorted keys, so each
  // draw only appends the runs newly below the cut — no per-frame hashing.
  buildRevealOrder() {
    this.reveal = this.groups.map((d) => {
      const n = d.length / 3;
      const key = new Float32Array(n);
      for (let k = 0; k < n; k++) {
        const x = d[k * 3];
        const y = d[k * 3 + 1];
        key[k] = (y / TUIST_DITHER.height) * (1 - REVEAL_JITTER) + particleHash(x, y) * REVEAL_JITTER;
      }
      const idx = Array.from({ length: n }, (_, k) => k);
      idx.sort((a, b) => key[a] - key[b]);
      const runs = new Float32Array(d.length);
      const sortedKey = new Float32Array(n);
      for (let dst = 0; dst < n; dst++) {
        const src = idx[dst];
        runs[dst * 3] = d[src * 3];
        runs[dst * 3 + 1] = d[src * 3 + 1];
        runs[dst * 3 + 2] = d[src * 3 + 2];
        sortedKey[dst] = key[src];
      }
      return { runs, key: sortedKey, drawn: 0 };
    });
  },

  // Per-particle physics state (current position + velocity), in artwork
  // space so it survives resizes. Built lazily on first hover.
  buildPhysics() {
    this.phys = this.reveal.map((g) => {
      const n = g.key.length;
      const cx = new Float32Array(n);
      const cy = new Float32Array(n);
      for (let k = 0; k < n; k++) {
        cx[k] = g.runs[k * 3];
        cy[k] = g.runs[k * 3 + 1];
      }
      return { cx, cy, vx: new Float32Array(n), vy: new Float32Array(n) };
    });
  },

  startPhysics() {
    if (this.physRaf !== null || this.progress < 1) return;
    if (!this.phys) this.buildPhysics();
    let last = performance.now();
    const tick = (now) => {
      const dt = Math.min((now - last) / 1000, 0.05);
      last = now;
      const settled = this.stepPhysics(dt);
      if (settled && !this.mouse) {
        this.snapToRest();
        this.draw();
        this.physRaf = null;
        return;
      }
      this.drawPhysics();
      this.physRaf = requestAnimationFrame(tick);
    };
    this.physRaf = requestAnimationFrame(tick);
  },

  // One physics step (dither-tool's model): cubic-falloff push away from
  // the cursor, spring back to rest, friction, then a position decay that
  // caps how far the trail can stretch. Returns true when everything has
  // settled back to rest.
  stepPhysics(dt) {
    const m = this.mouse;
    const f = dt * 60;
    const radiusSq = PHYS_RADIUS * PHYS_RADIUS;
    const decayD = 1 - Math.pow(1 - PHYS_DECAY, f);
    let maxSq = 0;
    for (let s = 0; s < this.phys.length; s++) {
      const runs = this.reveal[s].runs;
      const { cx, cy, vx, vy } = this.phys[s];
      for (let k = 0; k < cx.length; k++) {
        const rx = runs[k * 3];
        const ry = runs[k * 3 + 1];
        if (m) {
          const dx = cx[k] - m.x;
          const dy = cy[k] - m.y;
          const dSq = dx * dx + dy * dy;
          if (dSq < radiusSq && dSq > 0.01) {
            const dist = Math.sqrt(dSq);
            const t = 1 - dist / PHYS_RADIUS;
            const force = PHYS_PUSH * t * t * t * f;
            vx[k] += (dx / dist) * force;
            vy[k] += (dy / dist) * force;
          }
        }
        vx[k] += (rx - cx[k]) * PHYS_RETURN;
        vy[k] += (ry - cy[k]) * PHYS_RETURN;
        vx[k] *= PHYS_FRICTION;
        vy[k] *= PHYS_FRICTION;
        cx[k] += vx[k] * f;
        cy[k] += vy[k] * f;
        cx[k] += (rx - cx[k]) * decayD;
        cy[k] += (ry - cy[k]) * decayD;
        const ox = cx[k] - rx;
        const oy = cy[k] - ry;
        const sq = Math.max(ox * ox + oy * oy, vx[k] * vx[k] + vy[k] * vy[k]);
        if (sq > maxSq) maxSq = sq;
      }
    }
    return maxSq < PHYS_SETTLE * PHYS_SETTLE;
  },

  snapToRest() {
    for (let s = 0; s < this.phys.length; s++) {
      const runs = this.reveal[s].runs;
      const { cx, cy, vx, vy } = this.phys[s];
      for (let k = 0; k < cx.length; k++) {
        cx[k] = runs[k * 3];
        cy[k] = runs[k * 3 + 1];
      }
      vx.fill(0);
      vy.fill(0);
    }
  },

  // Full-frame render at the particles' current (displaced) positions;
  // only used while the physics loop is live.
  drawPhysics() {
    const { ctx } = this;
    const scale = this.width / TUIST_DITHER.width;
    const h = TUIST_DITHER.cell * scale;
    ctx.clearRect(0, 0, this.width, this.height);
    if (this.backdrop) {
      ctx.globalAlpha = 1;
      ctx.drawImage(this.backdrop, 0, 0, this.width, this.height);
    }
    ctx.globalAlpha = this.opacity;
    for (let s = 0; s < this.reveal.length; s++) {
      ctx.fillStyle = this.colors[s];
      const runs = this.reveal[s].runs;
      const { cx, cy } = this.phys[s];
      for (let k = 0; k < cx.length; k++) {
        ctx.fillRect(cx[k] * scale, cy[k] * scale, runs[k * 3 + 2] * scale, h);
      }
    }
  },

  startReveal() {
    if (this.raf !== null || this.progress >= 1) return;
    const start = performance.now();
    let lastTick = -1;
    const tick = (now) => {
      const step = Math.floor((now / 1000) * REVEAL_TICK_HZ);
      if (step !== lastTick) {
        lastTick = step;
        this.progress = Math.min(1, (now - start) / REVEAL_MS);
        this.draw();
      }
      this.raf = this.progress < 1 ? requestAnimationFrame(tick) : null;
    };
    this.raf = requestAnimationFrame(tick);
  },

  // Opaque background-colored silhouette derived from the particles (drawn,
  // blurred to close the inter-dot gaps, thresholded). Painted under the
  // translucent dither so the grid lines don't show through the logo.
  buildBackdrop() {
    const w = TUIST_DITHER.width;
    const h = TUIST_DITHER.height;
    const cell = TUIST_DITHER.cell;
    const solid = document.createElement("canvas");
    solid.width = w;
    solid.height = h;
    const sctx = solid.getContext("2d");
    sctx.fillStyle = "#000";
    for (const d of this.groups) {
      for (let i = 0; i < d.length; i += 3) {
        sctx.fillRect(d[i], d[i + 1], d[i + 2], cell);
      }
    }
    const blurred = document.createElement("canvas");
    blurred.width = w;
    blurred.height = h;
    const bctx = blurred.getContext("2d");
    bctx.filter = "blur(6px)";
    bctx.drawImage(solid, 0, 0);
    const img = bctx.getImageData(0, 0, w, h);
    const bg = colorBytes(resolveTokenColor(this.host, "--noora-surface-background-primary"));
    const data = img.data;
    for (let i = 0; i < data.length; i += 4) {
      if (data[i + 3] > 20) {
        data[i] = bg[0];
        data[i + 1] = bg[1];
        data[i + 2] = bg[2];
        data[i + 3] = 255;
      } else {
        data[i + 3] = 0;
      }
    }
    bctx.putImageData(img, 0, 0);
    this.backdrop = blurred;
  },

  draw() {
    if (!this.reveal || !this.layerCtx) return;
    const { ctx } = this;
    const p = this.progress === undefined ? 1 : this.progress;
    const cut = p >= 1 ? Infinity : p;
    // Append newly admitted runs to the persistent layer — everything drawn
    // on earlier ticks is already there.
    const lctx = this.layerCtx;
    const scale = this.width / TUIST_DITHER.width;
    const h = TUIST_DITHER.cell * scale;
    for (let shade = 0; shade < this.reveal.length; shade++) {
      const g = this.reveal[shade];
      const total = g.key.length;
      if (g.drawn >= total || g.key[g.drawn] > cut) continue;
      lctx.fillStyle = this.colors[shade];
      let k = g.drawn;
      for (; k < total && g.key[k] <= cut; k++) {
        lctx.fillRect(g.runs[k * 3] * scale, g.runs[k * 3 + 1] * scale, g.runs[k * 3 + 2] * scale, h);
      }
      g.drawn = k;
    }
    ctx.clearRect(0, 0, this.width, this.height);
    if (this.backdrop) {
      // Background-colored silhouette; fading it with the reveal eases the
      // grid lines out instead of blanking them at once.
      ctx.globalAlpha = p < 1 ? p : 1;
      ctx.drawImage(this.backdrop, 0, 0, this.width, this.height);
    }
    ctx.globalAlpha = this.opacity;
    ctx.drawImage(this.layer, 0, 0, this.width, this.height);
  },
};
