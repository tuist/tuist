/*
 * Dither globe (cache "Low latency, everywhere" card): a slowly spinning
 * stippled sphere — lat/long wireframe, Natural Earth coastlines, land
 * fill and ocean grain — rendered through the marketing dither texture:
 * every dot snaps to the 2px cell grid as a full 2px square, colored from
 * the shallow → mid → deep token ramp (interleaved per cell with a stable
 * hash so the shades scatter instead of banding), and the spin advances at
 * full rAF rate so the rotation stays smooth at chunky pitches. Dragging
 * the canvas rotates the globe (trackball); under prefers-reduced-motion
 * the globe holds a static frame.
 *
 * Options (all data attributes):
 *   data-size:      globe radius as a fraction of min(w, h) / 2
 *   data-pitch:     dither cell/dot size in px (the texture's grain)
 *   data-tilt-x:    forward tilt in radians
 *   data-tilt-z:    sideways tilt in radians
 *   data-speed:     spin in rad/s around the globe's own pole
 *   data-meridians: meridian great circles
 *   data-parallels: parallel rings
 *   data-density:   0-100 — arc spacing of the wireframe/coastline dots
 *   data-shade:     0-100 — terminator shading stipple amount
 *   data-land:      0-100 — land fill stipple amount
 *   data-ocean:     0-100 — ocean grain stipple amount
 *   data-offset-x / data-offset-y: center offset in px
 */

import { onThemeChange } from "../lib/theme.js";

// Deterministic hash in [0, 1): stable per cell, so the shade interleave
// never reshuffles between frames.
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

/* ---------- 3x3 rotation helpers --------------------------------- */
function matMul(a, b) {
  const o = new Array(9);
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 3; c++) {
      o[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c];
    }
  }
  return o;
}

function rotAxis(ax, ay, az, ang) {
  const l = Math.hypot(ax, ay, az) || 1;
  ax /= l;
  ay /= l;
  az /= l;
  const c = Math.cos(ang);
  const s = Math.sin(ang);
  const t = 1 - c;
  return [
    t * ax * ax + c,
    t * ax * ay - s * az,
    t * ax * az + s * ay,
    t * ax * ay + s * az,
    t * ay * ay + c,
    t * ay * az - s * ax,
    t * ax * az - s * ay,
    t * ay * az + s * ax,
    t * az * az + c,
  ];
}

const IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1];

/* ---------- lighting (view space, top-left-front) ----------------- */
const L = (() => {
  const v = [-0.45, 0.55, 0.72];
  const l = Math.hypot(...v);
  return v.map((x) => x / l);
})();

/* ---------- fixed stipple field on the sphere ---------------------
   Built lazily on first mount (with the land classification and the
   coastline subdivision below): this module is imported by every
   marketing page's bundle, and doing the geometry at import time held
   up first paint everywhere. */
const STIP_N = 22000;
let stip = null; // x, y, z, rand
let landFlag = null;

function ensureGeometry() {
  if (stip) return;
  stip = new Float32Array(STIP_N * 4);
  const ga = Math.PI * (3 - Math.sqrt(5));
  let seed = 1234567;
  const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  for (let i = 0; i < STIP_N; i++) {
    const y = 1 - ((i + 0.5) * 2) / STIP_N;
    const r = Math.sqrt(1 - y * y);
    const th = ga * i;
    stip[i * 4] = Math.cos(th) * r;
    stip[i * 4 + 1] = y;
    stip[i * 4 + 2] = Math.sin(th) * r;
    stip[i * 4 + 3] = rnd();
  }

  // Land classification via a rasterized equirectangular mask: one
  // native even-odd fill plus 22k cheap texel lookups, instead of 22k
  // point-in-polygon tests over the LAND rings (which took hundreds of
  // milliseconds).
  const MW = 1440;
  const MH = 720;
  const mask = document.createElement("canvas");
  mask.width = MW;
  mask.height = MH;
  const mctx = mask.getContext("2d", { willReadFrequently: true });
  const path = new Path2D();
  for (const r of getLand()) {
    path.moveTo(((r[0] + 1800) / 3600) * MW, ((900 - r[1]) / 1800) * MH);
    for (let i = 2; i < r.length; i += 2) {
      path.lineTo(((r[i] + 1800) / 3600) * MW, ((900 - r[i + 1]) / 1800) * MH);
    }
    path.closePath();
  }
  mctx.fillStyle = "#fff";
  mctx.fill(path, "evenodd");
  const data = mctx.getImageData(0, 0, MW, MH).data;
  landFlag = new Uint8Array(STIP_N);
  for (let i = 0; i < STIP_N; i++) {
    const x = stip[i * 4];
    const y = stip[i * 4 + 1];
    const z = stip[i * 4 + 2];
    const lat = Math.asin(Math.max(-1, Math.min(1, y)));
    const lon = Math.atan2(x, z);
    const mx = Math.min(MW - 1, ((lon / Math.PI + 1) / 2) * MW) | 0;
    const my = Math.min(MH - 1, (0.5 - lat / Math.PI) * MH) | 0;
    landFlag[i] = data[(my * MW + mx) * 4 + 3] > 127 ? 1 : 0;
  }
}

/* ---------- world map (Natural Earth 110m land, quantized x10) ----
   Packed as a zigzag-varint delta stream (base64) instead of a JS
   number literal: the raw ring array was ~20kB of digits that survived
   minification, tripling the hook's bundle cost. Decoding reproduces
   the exact same rings (verified bit-identical), so the coastlines and
   the land mask are unchanged. Regenerate with a script that walks the
   rings emitting zigzag varints: ring count, then per ring point count,
   absolute first point, and per-point deltas, all in 0.1-degree units. */
const LAND_B64 =
  "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";

let LAND = null;
function getLand() {
  if (LAND) return LAND;
  const s = atob(LAND_B64);
  let p = 0;
  const next = () => {
    let u = 0;
    let sh = 0;
    let b;
    do {
      b = s.charCodeAt(p++);
      u |= (b & 127) << sh;
      sh += 7;
    } while (b & 128);
    return (u >>> 1) ^ -(u & 1);
  };
  LAND = [];
  for (let n = next(); n > 0; n--) {
    const cnt = next();
    const r = new Int16Array(cnt * 2);
    r[0] = next();
    r[1] = next();
    for (let i = 2; i < cnt * 2; i += 2) {
      r[i] = r[i - 2] + next();
      r[i + 1] = r[i - 1] + next();
    }
    LAND.push(r);
  }
  return LAND;
}

const DEG = Math.PI / 180;
function ll2xyz(lon, lat) {
  const cf = Math.cos(lat * DEG);
  return [cf * Math.sin(lon * DEG), Math.sin(lat * DEG), cf * Math.cos(lon * DEG)];
}

/* coastlines: pre-subdivided 3D polylines on the sphere, built on
   first use */
let COAST = null;
function getCoast() {
  if (!COAST) {
    COAST = getLand().map(subdivideRing);
  }
  return COAST;
}

function subdivideRing(r) {
  const pts = [];
  const n = r.length / 2;
  let prev = ll2xyz(r[0] / 10, r[1] / 10);
  pts.push(prev[0], prev[1], prev[2]);
  for (let i = 1; i <= n; i++) {
    const ii = i % n;
    const cur = ll2xyz(r[ii * 2] / 10, r[ii * 2 + 1] / 10);
    const d = Math.max(-1, Math.min(1, prev[0] * cur[0] + prev[1] * cur[1] + prev[2] * cur[2]));
    const ang = Math.acos(d);
    const steps = Math.max(1, Math.ceil(ang / 0.02));
    for (let s = 1; s <= steps; s++) {
      const t = s / steps;
      const x = prev[0] + (cur[0] - prev[0]) * t;
      const y = prev[1] + (cur[1] - prev[1]) * t;
      const z = prev[2] + (cur[2] - prev[2]) * t;
      const l = Math.hypot(x, y, z) || 1;
      pts.push(x / l, y / l, z / l);
    }
    prev = cur;
  }
  return new Float32Array(pts);
}

/* Anchored grid dots — fixed positions ON the sphere, cached per M/P/step.
   Dots are glued to the globe like paint: rotation moves them, never
   re-seats them, so lines can't crawl or "regenerate" mid-spin. */
let gridCache = { key: "", pts: null };
function gridDots(M, P, step) {
  const key = M + "|" + P + "|" + step.toFixed(4);
  if (gridCache.key === key) return gridCache.pts;
  const out = [];
  for (let j = 0; j < M; j++) {
    const lon = (j * Math.PI) / M;
    const cl = Math.cos(lon);
    const sl = Math.sin(lon);
    const n = Math.max(8, Math.round((Math.PI * 2) / step));
    for (let i = 0; i < n; i++) {
      const t = (i / n) * Math.PI * 2;
      const st = Math.sin(t);
      out.push(st * cl, Math.cos(t), st * sl);
    }
  }
  for (let k = 1; k <= P; k++) {
    const lat = -Math.PI / 2 + (k * Math.PI) / (P + 1);
    const r = Math.cos(lat);
    const y = Math.sin(lat);
    const n = Math.max(6, Math.round((Math.PI * 2 * r) / step));
    for (let i = 0; i < n; i++) {
      const t = (i / n) * Math.PI * 2;
      out.push(r * Math.cos(t), y, r * Math.sin(t));
    }
  }
  gridCache = { key, pts: new Float32Array(out) };
  return gridCache.pts;
}

/* anchored coastline dots — walked once along the polylines in object
   space at fixed 3D arc spacing, cached per step */
let coastCache = { key: "", pts: null };
function coastDots(step) {
  const key = step.toFixed(4);
  if (coastCache.key === key) return coastCache.pts;
  const out = [];
  for (const pts of getCoast()) {
    let acc = step;
    for (let i = 3; i < pts.length; i += 3) {
      const dx = pts[i] - pts[i - 3];
      const dy = pts[i + 1] - pts[i - 2];
      const dz = pts[i + 2] - pts[i - 1];
      acc += Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (acc >= step) {
        acc = 0;
        out.push(pts[i], pts[i + 1], pts[i + 2]);
      }
    }
  }
  coastCache = { key, pts: new Float32Array(out) };
  return coastCache.pts;
}

/* Region markers: pulsing purple points glued to real locations on the
   sphere — they rotate with the globe and hide behind the horizon. No
   labels, just the pulse. */
const MARKERS = [
  [-0.1, 51.5], // EU West — London
  [8.7, 50.1], // EU Central — Frankfurt
  [-77.5, 38.9], // US East — N. Virginia
  [-122.7, 45.5], // US West — Oregon
  [-100.4, 20.6], // Mexico — Querétaro
  [-46.6, -23.5], // Brazil — São Paulo
  [31.2, 30.0], // North Africa — Cairo
  [72.9, 19.1], // India — Mumbai
  [103.8, 1.35], // Asia — Singapore
  [139.7, 35.7], // Japan — Tokyo
  [151.2, -33.9], // Australia — Sydney
].map(([lon, lat]) => ll2xyz(lon, lat));

const PULSE_S = 2.4; // one ring per marker every PULSE_S seconds, staggered

// The tunable options and their data-attribute names.
const OPTIONS = [
  { key: "size", attr: "size", def: 0.78 },
  { key: "pitch", attr: "pitch", def: 2 },
  { key: "tiltX", attr: "tilt-x", def: 0.42 },
  { key: "tiltZ", attr: "tilt-z", def: -0.25 },
  { key: "speed", attr: "speed", def: 0.25 },
  { key: "meridians", attr: "meridians", def: 9 },
  { key: "parallels", attr: "parallels", def: 9 },
  { key: "density", attr: "density", def: 40 },
  { key: "shade", attr: "shade", def: 30 },
  { key: "land", attr: "land", def: 55 },
  { key: "ocean", attr: "ocean", def: 20 },
  { key: "offsetX", attr: "offset-x", def: 0 },
  { key: "offsetY", attr: "offset-y", def: 0 },
];

export const DitherGlobe = {
  mounted() {
    ensureGeometry();
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.parentElement;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.raf = null;
    this.visible = false;
    this.spin = 0;
    this.pulseT = 0;
    this.drag = IDENTITY;

    this.opts = {};
    for (const o of OPTIONS) {
      const raw = this.el.dataset[o.attr.replace(/-(\w)/g, (_, c) => c.toUpperCase())];
      const n = raw === undefined ? NaN : Number(raw);
      this.opts[o.key] = Number.isFinite(n) ? n : o.def;
    }

    this.resolveColors = () => {
      this.shades = [
        resolveTokenColor(this.host, "--marketing-cache-globe-dither-shallow"),
        resolveTokenColor(this.host, "--marketing-cache-globe-dither-mid"),
        resolveTokenColor(this.host, "--marketing-cache-globe-dither-deep"),
      ];
      // Pre-packed ABGR words for the pixel-buffer renderer.
      this.packedShades = this.shades.map((s) => ((255 << 24) | (s[2] << 16) | (s[1] << 8) | s[0]) >>> 0);
      this.markerShade = resolveTokenColor(this.host, "--marketing-cache-globe-marker");
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.render();
    });

    this.resize = () => {
      const rect = this.host.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.render();
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.host);
    this.resize();

    // Spin only while on screen (and never under reduced motion — the
    // globe then holds the frame it mounted with).
    this.viewObserver = new IntersectionObserver(
      ([entry]) => {
        this.visible = entry.isIntersecting;
        if (this.visible && !this.reduced) this.start();
        else this.stop();
      },
      { threshold: 0.05 },
    );
    this.viewObserver.observe(this.host);

    /* drag to rotate (trackball, view space) */
    this.dragging = false;
    this.onPointerDown = (e) => {
      this.dragging = true;
      this.lx = e.clientX;
      this.ly = e.clientY;
      this.canvas.classList.add("dragging");
      this.canvas.setPointerCapture(e.pointerId);
    };
    this.onPointerMove = (e) => {
      if (!this.dragging) return;
      const dx = e.clientX - this.lx;
      const dy = e.clientY - this.ly;
      this.lx = e.clientX;
      this.ly = e.clientY;
      const len = Math.hypot(dx, dy);
      if (len > 0) {
        const k = 3.1 / Math.min(this.w, this.h);
        this.drag = matMul(rotAxis(dy, dx, 0, len * k), this.drag);
        if (this.raf === null) this.render();
      }
    };
    this.onPointerUp = () => {
      this.dragging = false;
      this.canvas.classList.remove("dragging");
    };
    this.canvas.addEventListener("pointerdown", this.onPointerDown);
    this.canvas.addEventListener("pointermove", this.onPointerMove);
    this.canvas.addEventListener("pointerup", this.onPointerUp);
    this.canvas.addEventListener("pointercancel", this.onPointerUp);

    this.render();
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.observer) this.observer.disconnect();
    if (this.viewObserver) this.viewObserver.disconnect();
    this.stop();
    this.canvas.removeEventListener("pointerdown", this.onPointerDown);
    this.canvas.removeEventListener("pointermove", this.onPointerMove);
    this.canvas.removeEventListener("pointerup", this.onPointerUp);
    this.canvas.removeEventListener("pointercancel", this.onPointerUp);
  },

  start() {
    if (this.raf !== null) return;
    this.lastTime = performance.now();
    // Full rAF rate (~60fps): with chunky pitch cells a quantized cadence
    // reads as jitter, so the rotation advances every frame — the dots
    // still snap to the cell grid, they just step far more often.
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      const dt = Math.min((now - this.lastTime) / 1000, 0.25);
      this.lastTime = now;
      if (!this.dragging) this.spin += this.opts.speed * dt;
      this.pulseT += dt;
      this.render();
    };
    this.raf = requestAnimationFrame(tick);
  },

  stop() {
    if (this.raf !== null) {
      cancelAnimationFrame(this.raf);
      this.raf = null;
    }
  },

  // drag (view) * tilt (posing) * spin (own pole) — sliders keep working
  // after a drag, and the spin never disturbs the tilt.
  rotation() {
    const tilt = matMul(rotAxis(1, 0, 0, this.opts.tiltX), rotAxis(0, 0, 1, this.opts.tiltZ));
    return matMul(this.drag, matMul(tilt, rotAxis(0, 1, 0, this.spin)));
  },

  /* Walk the globe's dots — wireframe, coastlines, stipple fill — and
     hand each to plot(wx, wy, n): unit-sphere view coordinates plus a
     signal n in 0..1, how deep into the shade ramp the dot sits. Dots are
     drawn straight through the callback: the old per-frame array of dot
     objects churned the GC at 60fps. */
  drawField(plot) {
    const R = this.rotation();
    const M = Math.round(this.opts.meridians);
    const P = Math.round(this.opts.parallels);
    const spacing = 0.055 - (this.opts.density / 100) * 0.041;
    const shadeAmt = this.opts.shade / 100;
    const landAmt = this.opts.land / 100;
    const oceanAmt = this.opts.ocean / 100;
    const m0 = R[0];
    const m1 = R[1];
    const m2 = R[2];
    const m3 = R[3];
    const m4 = R[4];
    const m5 = R[5];
    const m6 = R[6];
    const m7 = R[7];
    const m8 = R[8];
    const L0 = L[0];
    const L1 = L[1];
    const L2 = L[2];

    // rotate anchored dots, cull the back hemisphere, shade by darkness
    const anchored = (pts, base, span) => {
      for (let i = 0; i < pts.length; i += 3) {
        const x = pts[i];
        const y = pts[i + 1];
        const z = pts[i + 2];
        const wz = m6 * x + m7 * y + m8 * z;
        if (wz <= 0.015) continue;
        const wx = m0 * x + m1 * y + m2 * z;
        const wy = m3 * x + m4 * y + m5 * z;
        let b = (wx * L0 + wy * L1 + wz * L2) * 0.5 + 0.5;
        if (b < 0) b = 0;
        else if (b > 1) b = 1;
        plot(wx, wy, base + span * (1 - b));
      }
    };
    anchored(gridDots(M, P, spacing), 0.35, 0.45);
    if (landAmt > 0) anchored(coastDots(spacing * 0.62), 0.55, 0.45);

    // surface stipple — land fill + ocean grain + terminator shading
    if (shadeAmt > 0 || landAmt > 0 || oceanAmt > 0) {
      for (let i = 0; i < STIP_N; i++) {
        const x = stip[i * 4];
        const y = stip[i * 4 + 1];
        const z = stip[i * 4 + 2];
        // depth-only test first — skips ~half the points before full transform
        const wz = m6 * x + m7 * y + m8 * z;
        if (wz < 0.03) continue;
        const wx = m0 * x + m1 * y + m2 * z;
        const wy = m3 * x + m4 * y + m5 * z;
        let b = (wx * L0 + wy * L1 + wz * L2) * 0.5 + 0.5;
        if (b < 0) b = 0;
        else if (b > 1) b = 1;
        const d = 1 - b;
        const rnd = stip[i * 4 + 3];
        if (landAmt > 0 && landFlag[i]) {
          // land: reads on the lit side too, thickens toward shadow
          if (landAmt * (0.55 + 0.6 * d) > rnd) plot(wx, wy, 0.45 + 0.55 * d);
        } else if (shadeAmt > 0 && i % 3 === 0 && Math.pow(d, 2.6) * shadeAmt * 1.35 > rnd) {
          plot(wx, wy, 0.3 + 0.5 * d);
        } else if (oceanAmt > 0 && oceanAmt * 0.5 * (0.55 + 0.55 * d) > rnd) {
          // fine, sparse water grain — shallowest shades, so land stays darker
          plot(wx, wy, 0.2 + 0.3 * d);
        }
      }
    }
  },

  render() {
    const { ctx, w, h, shades } = this;
    if (!w || !h) return;
    ctx.clearRect(0, 0, w, h);
    const rad = (Math.min(w, h) / 2) * this.opts.size;
    const cx = w / 2 + this.opts.offsetX;
    const cy = h / 2 + this.opts.offsetY;
    const pitch = Math.max(1, Math.round(this.opts.pitch));
    // Pixel-buffer rendering: thousands of per-dot fillRect calls (with a
    // fillStyle change each) dominated the frame cost and starved the
    // page's other animations. Dots are written straight into an
    // ImageData word buffer and blitted once, nearest-neighbor, which
    // also keeps the pixel-art crisp.
    if (!this.buf || this.bufW !== w || this.bufH !== h) {
      this.off = document.createElement("canvas");
      this.off.width = w;
      this.off.height = h;
      this.offCtx = this.off.getContext("2d");
      this.buf = this.offCtx.createImageData(w, h);
      this.buf32 = new Uint32Array(this.buf.data.buffer);
      this.bufW = w;
      this.bufH = h;
    }
    const buf32 = this.buf32;
    buf32.fill(0);
    const packed = this.packedShades;
    // Snap to the pitch cell grid — the dither texture's chunky grain.
    // Seamless ramp: the signal maps to a continuous position across the
    // three shades, and each dot dithers between its two nearest shades
    // via the stable cell hash — the colors interleave instead of
    // stacking into visible bands.
    this.drawField((wx, wy, n) => {
      const gx = Math.round((cx + wx * rad) / pitch);
      const gy = Math.round((cy - wy * rad) / pitch);
      const s = Math.min(2, n * 2);
      const lo = Math.floor(s);
      const hi = Math.min(2, lo + 1);
      const color = packed[s - lo > noise2(gx + 31, gy + 17) ? hi : lo];
      const x0 = gx * pitch;
      const y0 = gy * pitch;
      if (x0 >= 0 && y0 >= 0 && x0 + pitch <= w && y0 + pitch <= h) {
        // fully-inside block: skip the per-pixel bounds checks (hot path —
        // nearly every dot lands here; only limb dots at the canvas edge
        // need clipping)
        let row = y0 * w + x0;
        for (let py = 0; py < pitch; py++, row += w) {
          for (let px = 0; px < pitch; px++) {
            buf32[row + px] = color;
          }
        }
      } else {
        for (let py = y0; py < y0 + pitch; py++) {
          if (py < 0 || py >= h) continue;
          const row = py * w;
          for (let px = x0; px < x0 + pitch; px++) {
            if (px < 0 || px >= w) continue;
            buf32[row + px] = color;
          }
        }
      }
    });
    this.offCtx.putImageData(this.buf, 0, 0);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(this.off, 0, 0, w, h);
    this.renderMarkers(pitch, rad, cx, cy);
  },

  /* Pulsing region markers, drawn on top of the globe as plain vector
     shapes (no dither): a solid purple core plus an expanding stroked
     ring that fades out with alpha as it grows. Core and ring live on the
     sphere's tangent plane at the marker, so they project as foreshortened
     ellipses hugging the surface — tilting with the globe and squashing
     toward the limb — instead of flat screen circles. Markers fade out
     near the horizon and under prefers-reduced-motion only the static
     cores show. */
  renderMarkers(pitch, rad, cx, cy) {
    const { ctx } = this;
    const R = this.rotation();
    const [mr, mg, mb] = this.markerShade;
    const color = `rgb(${mr}, ${mg}, ${mb})`;
    const coreR = Math.max(pitch * 1.5, rad * 0.028) / rad;
    const maxRing = coreR + 0.11;
    for (let i = 0; i < MARKERS.length; i++) {
      const [x, y, z] = MARKERS[i];
      const wz = R[6] * x + R[7] * y + R[8] * z;
      if (wz <= 0.12) continue;
      const limb = Math.min(1, (wz - 0.12) / 0.3);
      const wx = R[0] * x + R[1] * y + R[2] * z;
      const wy = R[3] * x + R[4] * y + R[5] * z;
      const px = cx + wx * rad;
      const py = cy - wy * rad;
      // Tangent basis at the marker (view space): t1 ⟂ the surface normal
      // and horizontal-ish, t2 = n × t1. Their screen projections become
      // the canvas transform, so a unit circle drawn under it lands as the
      // tangent-plane ellipse.
      let t1x = wz;
      let t1z = -wx;
      const t1l = Math.hypot(t1x, t1z) || 1;
      t1x /= t1l;
      t1z /= t1l;
      const t2x = wy * t1z;
      const t2y = wz * t1x - wx * t1z;
      const a = t1x * rad;
      const b = t2x * rad;
      const d = -t2y * rad;
      if (Math.abs(a * d) < 1e-6) continue;
      ctx.save();
      ctx.transform(a, 0, b, d, px, py);
      ctx.fillStyle = color;
      ctx.globalAlpha = limb;
      ctx.beginPath();
      ctx.arc(0, 0, coreR, 0, Math.PI * 2);
      ctx.fill();
      if (!this.reduced) {
        // Stagger the phases so the pulses ripple around the globe
        // instead of firing in unison.
        const t = (this.pulseT / PULSE_S + i * 0.37) % 1;
        const ringR = coreR + t * (maxRing - coreR);
        ctx.strokeStyle = color;
        ctx.globalAlpha = (1 - t) * 0.9 * limb;
        ctx.lineWidth = Math.max(1.25, pitch) / rad;
        ctx.beginPath();
        ctx.arc(0, 0, ringR, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.restore();
    }
  },
};
