/*
 * Community grid — the Tuist burst as pre-dithered particles.
 *
 * The artwork is the brand mark's outline bayer-dithered into four mono
 * shades on a 2px grid (~5k single-cell particles, 568×568 — a filled mark
 * was ~47k and made the hover physics crawl) and baked into a packed
 * data module by assets/marketing/scripts/bake_tuist_dither.py (see
 * tuist-dither-data.js) — no runtime fetch or SVG parsing. The hook
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
 * After the reveal, hovering scatters the particles (look modeled on
 * asmitbm/dither-tool): each particle owes a displacement target — its rest
 * spot pushed radially away from the cursor with a cubic falloff — and
 * chases it with an under-damped spring, which gives the overshoot and the
 * trailing lag behind a sweeping cursor. The target is a pure function of
 * the cursor and the rest position, so a stationary cursor yields a
 * stationary equilibrium the spring provably converges to (a force
 * integrator here had a limit cycle: particles under a still cursor
 * jittered forever, worse on slow frames). The loop pauses whenever both
 * movement and spring tension die out — equilibrium under the cursor or
 * fully returned — and mousemove/mouseleave restart it. Static under
 * prefers-reduced-motion.
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

// Hover physics (artwork px where relevant). Particles chase their target
// with an under-damped spring: stiffness sets the tempo (settle time is
// roughly 2π/√stiffness), damping sets the bounce — critical damping is
// 2·√stiffness (≈19 here), lower rings longer. The current pair is soft
// and clearly under critical (damping ratio ≈0.63): particles lag well
// behind a sweeping cursor and overshoot on the way back, so a pass leaves
// a visible trail instead of a tight halo.
const PHYS_RADIUS = 64; // cursor influence radius
const PHYS_PUSH = 36; // max radial displacement at the cursor core
const PHYS_STIFFNESS = 90; // spring stiffness toward the target, 1/s²
const PHYS_DAMPING = 12; // velocity decay, 1/s
const PHYS_SETTLE = 0.05; // movement AND spring tension below this = settled

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

// Unpack a base64 string of little-endian 32-bit words.
function decodeWords(b64, count) {
  const bin = atob(b64);
  const words = new Uint32Array(count);
  for (let i = 0; i < words.length; i++) {
    const o = i * 4;
    words[i] =
      bin.charCodeAt(o) | (bin.charCodeAt(o + 1) << 8) | (bin.charCodeAt(o + 2) << 16) | (bin.charCodeAt(o + 3) << 24);
  }
  return words;
}

// Decode the packed runs into one flat [x, y, w] array per shade (px units;
// runs are `cell` px tall).
function decodeRuns() {
  const cell = TUIST_DITHER.cell;
  const counts = [0, 0, 0, 0];
  const words = decodeWords(TUIST_DITHER.data, TUIST_DITHER.runs);
  for (let i = 0; i < words.length; i++) counts[(words[i] >>> 27) & 3]++;
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

// The filled silhouette's per-row spans as a flat [x, y, w] array (px).
function decodeFill() {
  const cell = TUIST_DITHER.cell;
  const words = decodeWords(TUIST_DITHER.fill, TUIST_DITHER.fillRuns);
  const spans = new Float32Array(words.length * 3);
  for (let i = 0; i < words.length; i++) {
    const v = words[i];
    spans[i * 3] = (v & 511) * cell;
    spans[i * 3 + 1] = ((v >>> 9) & 511) * cell;
    spans[i * 3 + 2] = ((v >>> 18) & 511) * cell;
  }
  return spans;
}

export const TuistDitherParticles = {
  mounted() {
    // A bfcache restore re-mounts hooks without ever calling destroyed() on
    // the previous instance (see LogoTransition); tear the old one down so
    // two observers and reveal loops don't fight over the same canvas.
    if (this.el.ditherTeardown) this.el.ditherTeardown();
    this.el.ditherTeardown = () => this.teardown();

    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.parentElement;
    this.groups = decodeRuns();
    this.fill = decodeFill();
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
        // The loop pauses at equilibrium while hovered, so the return trip
        // needs an explicit restart.
        this.startPhysics();
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

    // The ResizeObserver only reacts to layout changes; a devicePixelRatio
    // change (moving the window to another display, browser zoom) leaves the
    // fixed-size box untouched, so the buffer would stay at the old density
    // and the upscale reads as blocky pixels. The media query matches the
    // current dpr only, so it fires exactly when the dpr moves off it —
    // re-arm against the new value each time.
    this.armDprWatch = () => {
      const dpr = window.devicePixelRatio || 1;
      this.dprQuery = window.matchMedia(`(resolution: ${dpr}dppx)`);
      this.onDprChange = () => {
        this.armDprWatch();
        this.resize();
      };
      this.dprQuery.addEventListener("change", this.onDprChange, { once: true });
    };
    this.armDprWatch();

    // Long-hidden tabs can have canvas backing stores evicted (the particle
    // layer comes back blank behind the composite), and a bfcache restore
    // resumes with whatever the buffers froze as; resize() rebuilds the
    // layer from scratch up to the current reveal cut, so run it on return.
    this.onVisible = () => {
      if (!document.hidden) this.resize();
    };
    document.addEventListener("visibilitychange", this.onVisible);
    this.onPageshow = (event) => {
      if (event.persisted) this.resize();
    };
    window.addEventListener("pageshow", this.onPageshow);

    this.resize();
  },

  destroyed() {
    this.teardown();
  },

  teardown() {
    if (this.el.ditherTeardown) this.el.ditherTeardown = null;
    if (this.offThemeChange) this.offThemeChange();
    if (this.observer) this.observer.disconnect();
    if (this.io) this.io.disconnect();
    if (this.raf !== null) cancelAnimationFrame(this.raf);
    if (this.physRaf !== null) cancelAnimationFrame(this.physRaf);
    if (this.gridEl) {
      this.gridEl.removeEventListener("mousemove", this.onMove);
      this.gridEl.removeEventListener("mouseleave", this.onLeave);
    }
    if (this.dprQuery) this.dprQuery.removeEventListener("change", this.onDprChange);
    document.removeEventListener("visibilitychange", this.onVisible);
    window.removeEventListener("pageshow", this.onPageshow);
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
      if (settled) {
        // Movement stopped: pause the loop instead of redrawing identical
        // frames (the redraw churn itself read as flicker on slower
        // browsers). Under a stationary cursor the scattered pose holds;
        // the next mousemove or mouseleave restarts the loop.
        this.physRaf = null;
        if (this.mouse) {
          this.drawPhysics();
        } else {
          this.snapToRest();
          this.draw();
        }
        return;
      }
      this.drawPhysics();
      this.physRaf = requestAnimationFrame(tick);
    };
    this.physRaf = requestAnimationFrame(tick);
  },

  // One step of the hover displacement. Each particle's target is its rest
  // spot pushed radially away from the cursor (cubic falloff, computed from
  // the REST position — no feedback from the current position, so the
  // target is a true fixed point). Positions chase the target with an
  // under-damped spring (semi-implicit Euler; damping applied as an exact
  // exponential so slow frames don't ring harder): the overshoot on the way
  // out and the lag behind a sweeping cursor are the spring/trail feel, and
  // because the target is fixed the spring provably converges — unlike the
  // old force integrator, which orbited a limit cycle under a still cursor.
  // Returns true only when both movement and remaining spring tension are
  // negligible, so the loop can't pause at the top of an overshoot arc.
  stepPhysics(dt) {
    const m = this.mouse;
    const damp = Math.exp(-PHYS_DAMPING * dt);
    const radiusSq = PHYS_RADIUS * PHYS_RADIUS;
    let maxSq = 0;
    for (let s = 0; s < this.phys.length; s++) {
      const runs = this.reveal[s].runs;
      const { cx, cy, vx, vy } = this.phys[s];
      for (let k = 0; k < cx.length; k++) {
        const rx = runs[k * 3];
        const ry = runs[k * 3 + 1];
        let tx = rx;
        let ty = ry;
        if (m) {
          const dx = rx - m.x;
          const dy = ry - m.y;
          const dSq = dx * dx + dy * dy;
          if (dSq < radiusSq) {
            const dist = Math.sqrt(dSq);
            const t = 1 - dist / PHYS_RADIUS;
            const push = PHYS_PUSH * t * t * t;
            if (dist > 0.01) {
              tx = rx + (dx / dist) * push;
              ty = ry + (dy / dist) * push;
            } else {
              // Cursor dead on the rest spot: push along a stable,
              // hash-picked direction instead of dividing by zero.
              const ang = particleHash(rx, ry) * 6.28318;
              tx = rx + Math.cos(ang) * push;
              ty = ry + Math.sin(ang) * push;
            }
          }
        }
        const ex = tx - cx[k];
        const ey = ty - cy[k];
        vx[k] = (vx[k] + ex * PHYS_STIFFNESS * dt) * damp;
        vy[k] = (vy[k] + ey * PHYS_STIFFNESS * dt) * damp;
        const mx = vx[k] * dt;
        const my = vy[k] * dt;
        cx[k] += mx;
        cy[k] += my;
        const sq = Math.max(mx * mx + my * my, ex * ex + ey * ey);
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

  // Opaque background-colored silhouette from the baked fill spans (drawn,
  // blurred to soften the cell steps, thresholded). Painted under the
  // translucent dither so the grid lines don't show through the logo — the
  // particles only trace its outline, so they can't stand in for it.
  buildBackdrop() {
    const w = TUIST_DITHER.width;
    const h = TUIST_DITHER.height;
    const cell = TUIST_DITHER.cell;
    const solid = document.createElement("canvas");
    solid.width = w;
    solid.height = h;
    const sctx = solid.getContext("2d");
    sctx.fillStyle = "#000";
    const fill = this.fill;
    for (let i = 0; i < fill.length; i += 3) {
      sctx.fillRect(fill[i], fill[i + 1], fill[i + 2], cell);
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
