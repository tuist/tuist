/*
 * The 404 outline view's portal: the dithered edge of the spotlight and
 * the particles the page sheds along it.
 *
 * Two parts, both driven by the NotFoundOutline hook:
 *
 * 1. `applyDitherMask` — the spotlight overlay's mask. Instead of a soft
 *    radial gradient the mask is an ordered dither: a stack of hard-edged
 *    discs at stepped radii, each intersected with a tile of Bayer
 *    thresholds at a falling density, composited with `mask-composite`.
 *    Read from the inside out: the innermost disc is solid; each ring
 *    beyond it keeps only the cells whose threshold is under that ring's
 *    density, so across the feather the outline view breaks up cell by
 *    cell into the real page, the way the site's dither textures break
 *    up. The tiles are pinned to the page's origin, so the cells stay put
 *    while the circle moves through them: the page is dithered, not the
 *    circle. The centre and radius are still the hook's custom properties,
 *    so every move animates exactly as before. Where `mask-composite` is
 *    missing the stylesheet's gradient mask stays.
 *
 * 2. `PortalDither` — the page's text fading away in dither particles
 *    where the two views swap. The mask does the fading itself (fill to
 *    stroke, cell by cell); this is a viewport-sized canvas over the
 *    overlay on which the cells that fade leave the letters: every text
 *    run in the navbar, hero and footer is rasterized once at the
 *    dither's cell size into a map of the cells its ink covers, and
 *    specks lift off those cells where the mask's band crosses them (the
 *    dither globe's recipe: a slow trickle, drifting outward with a
 *    little sway, in fast and out slowly), more of them while the circle
 *    moves. Nothing is drawn on the glyphs themselves, and nothing where
 *    there is no content. Positions are in page coordinates and drawn in
 *    the viewport, so scrolling does not drag them.
 */

import { onThemeChange } from "../lib/theme.js";

const PORTAL_ID = "marketing-outline-portal";
const INKS = 4; // --marketing-portal-ink-1 … -4

// ---------------------------------------------------------------- mask

const PITCH = 2; // css px per dither cell
const TILE_CELLS = 32; // cells per tile side (64px at pitch 2)
const LEVELS = 7; // rings across the feather, densest first
// Threshold jitter blended into the 8x8 Bayer matrix so the rings do not
// read as straight Bayer rows (the dither textures' data-noise).
const NOISE = 0.35;
const BAYER8 = [
  0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54,
  22, 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29,
  53, 21,
];

const hash = (n) => {
  const x = Math.sin(n * 12.9898) * 43758.5453;
  return x - Math.floor(x);
};

export const supportsDitherMask = () =>
  typeof CSS !== "undefined" &&
  (CSS.supports("mask-composite", "intersect") || CSS.supports("-webkit-mask-composite", "source-in"));

// One threshold per cell of the tile, shared by every level so the levels
// nest: a cell open at a low density is open at every higher one.
let thresholds = null;
const cellThresholds = () => {
  if (thresholds) return thresholds;
  thresholds = new Float32Array(TILE_CELLS * TILE_CELLS);
  for (let y = 0; y < TILE_CELLS; y++) {
    for (let x = 0; x < TILE_CELLS; x++) {
      const bayer = (BAYER8[(y & 7) * 8 + (x & 7)] + 0.5) / 64;
      const jitter = (hash(y * TILE_CELLS + x + 1) - 0.5) * NOISE;
      thresholds[y * TILE_CELLS + x] = Math.min(0.999, Math.max(0.001, bayer + jitter));
    }
  }
  return thresholds;
};

// The tiles are drawn at device resolution so their cells land on whole
// device pixels; cached per pixel ratio.
const tileCache = new Map();
const tiles = (dpr) => {
  const key = String(dpr);
  if (tileCache.has(key)) return tileCache.get(key);
  const cell = PITCH * dpr;
  const side = TILE_CELLS * cell;
  const t = cellThresholds();
  const urls = [];
  for (let level = 1; level <= LEVELS; level++) {
    const density = 1 - level / (LEVELS + 1);
    const canvas = document.createElement("canvas");
    canvas.width = side;
    canvas.height = side;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#000";
    for (let y = 0; y < TILE_CELLS; y++) {
      for (let x = 0; x < TILE_CELLS; x++) {
        if (t[y * TILE_CELLS + x] < density) ctx.fillRect(x * cell, y * cell, cell, cell);
      }
    }
    urls.push(`url("${canvas.toDataURL("image/png")}")`);
  }
  tileCache.set(key, urls);
  return urls;
};

const disc = (inset) =>
  `radial-gradient(circle at var(--marketing-outline-x) var(--marketing-outline-y), #000 calc(var(--marketing-outline-r) - ${inset}px), transparent calc(var(--marketing-outline-r) - ${inset}px))`;

// Layers, top first: disc, tile, disc, tile, …, disc. Composited from the
// bottom up, each disc adds to what is below and each tile intersects it,
// which works out to: solid inside the innermost disc, then each ring
// keeps its own tile's cells.
export function applyDitherMask(el, feather) {
  const dpr = window.devicePixelRatio || 1;
  const tileUrls = tiles(dpr);
  const images = [];
  const composite = [];
  const legacy = [];
  const sizes = [];
  const repeats = [];
  for (let level = 0; level <= LEVELS; level++) {
    images.push(disc(feather - (feather * level) / LEVELS));
    composite.push("add");
    legacy.push("source-over");
    sizes.push("auto");
    repeats.push("no-repeat");
    if (level < LEVELS) {
      images.push(tileUrls[level]);
      composite.push("intersect");
      legacy.push("source-in");
      sizes.push(`${TILE_CELLS * PITCH}px ${TILE_CELLS * PITCH}px`);
      repeats.push("repeat");
    }
  }
  const s = el.style;
  s.setProperty("-webkit-mask-image", images.join(", "));
  s.setProperty("-webkit-mask-size", sizes.join(", "));
  s.setProperty("-webkit-mask-repeat", repeats.join(", "));
  s.setProperty("-webkit-mask-position", "0 0");
  s.setProperty("-webkit-mask-composite", legacy.join(", "));
  s.setProperty("mask-image", images.join(", "));
  s.setProperty("mask-size", sizes.join(", "));
  s.setProperty("mask-repeat", repeats.join(", "));
  s.setProperty("mask-position", "0 0");
  s.setProperty("mask-composite", composite.join(", "));
}

// -------------------------------------------------------------- dither

const REGIONS = ["#marketing-navbar", "#marketing-not-found", "#marketing-footer"];
// Subtrees whose text never shows (menu panels, the mobile menu): their
// boxes still measure, so they are skipped by name as well as by
// visibility.
// The "404" figure is left out too: it is decoration, and a page-covering
// circle crossing it would otherwise litter it with specks.
const HIDDEN =
  '[data-part="viewport"], [data-part="mobile-menus"], [data-part="positioner"], [data-part="figure"], script, style, template, [hidden]';
// Ink coverage above which a cell of a rasterized run counts as glyph.
const INK_ALPHA = 80;
// How readily glyph cells at the edge itself shed specks; it ramps down
// from here toward the band's inner and outer ends.
const EDGE_DENSITY = 1;
// Inside the circle (past the band) nothing: the fading is the edge's,
// so a page-covering circle (pinning, unpinning) sheds nothing at all.
const INSIDE_DENSITY = 0;
// How far past the edge the band reaches, as a share of the feather.
const BAND_OUT = 0.5;
// Specks: the dither globe's recipe. A slow trickle of faint cells lifts
// off the glyphs in the band and drifts outward with a little sway,
// fading in fast and out slowly. Per second at rest, plus per px² the
// band sweeps as the circle moves.
const REST_RATE = 20;
const SWEEP_RATE = 0.002;
// Once the circle is gone the specks still alive fade out over this long,
// whatever their own age, so none outlive the restored page.
const GONE_FADE = 0.4;
const SPECK_SPEED = 40; // css px per second, outward
const SPECK_LIFE = 4.5; // seconds
const MAX_LOOSE = 900;
const MAX_SPAWN_PER_FRAME = 24;

export class PortalDither {
  constructor() {
    this.canvas = null;
    this.ctx = null;
    this.runs = null;
    this.loose = [];
    this.inks = null;
    this.frame = null;
    this.last = 0;
    this.emitAcc = 0;
    this.gone = 0;
    this.emit = true;
    this.x = 0;
    this.y = 0;
    this.r = 0;
    this.band = 64;
    this.lastR = 0;
    this.unsubscribe = onThemeChange(() => {
      this.inks = null;
    });
  }

  // Where the portal is now, in page coordinates, how wide its dithered
  // band is, and whether it should shed specks at all (the hook says no
  // while the circle is growing over or shrinking off the page: those
  // moves leave no remnants). Called every frame the hook moves or shows
  // the circle; radius zero means it is gone.
  set(x, y, r, band, emit = true) {
    this.x = x;
    this.y = y;
    this.r = r;
    this.emit = emit;
    if (band) this.band = band;
    if (r > 0) this.start();
  }

  // The layout changed: rasterize the content again on the next start.
  invalidate() {
    this.runs = null;
  }

  ensureCanvas() {
    if (this.canvas) return;
    const canvas = document.createElement("canvas");
    canvas.id = PORTAL_ID;
    canvas.setAttribute("aria-hidden", "true");
    document.body.append(canvas);
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
  }

  // The four inks, resolved through the canvas's registered custom
  // properties (so light-dark() comes back as a plain color).
  readInks() {
    const style = getComputedStyle(this.canvas);
    const inks = [];
    for (let n = 1; n <= INKS; n++) {
      inks.push(style.getPropertyValue(`--marketing-portal-ink-${n}`).trim() || style.color);
    }
    this.inks = inks;
    // Peak speck opacity is the theme's too (see outline-mode.css).
    const opacity = parseFloat(style.getPropertyValue("--marketing-portal-speck-opacity"));
    this.speckOpacity = Number.isFinite(opacity) ? opacity : 0.4;
  }

  // Every visible text run in the regions rasterized at cell size: for
  // each, the page position of its line box and the cells its glyphs
  // cover (as cell coordinates, interleaved x,y). Only glyphs: the boxes
  // are the outline view's to draw.
  rasterize() {
    const runs = [];
    const sx = window.scrollX;
    const sy = window.scrollY;
    const scratch = document.createElement("canvas");
    const ctx = scratch.getContext("2d", { willReadFrequently: true });
    const addRun = (x, y, w, h, cells) => {
      if (cells.length) runs.push({ x, y, w, h, cells, cx: x + w / 2, cy: y + h / 2, reach: Math.hypot(w, h) / 2 });
    };
    for (const selector of REGIONS) {
      const root = document.querySelector(selector);
      if (!root) continue;
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {
        if (!node.textContent.trim()) continue;
        const parent = node.parentElement;
        if (!parent || parent.closest(HIDDEN)) continue;
        if (parent.checkVisibility && !parent.checkVisibility({ visibilityProperty: true, opacityProperty: true })) {
          continue;
        }
        const style = getComputedStyle(parent);
        if (style.visibility === "hidden" || style.display === "none") continue;
        const range = document.createRange();
        range.selectNodeContents(node);
        const rects = range.getClientRects();
        if (!rects.length) continue;
        let text = node.textContent.replace(/\s+/g, " ").trim();
        if (style.textTransform === "uppercase") text = text.toUpperCase();
        else if (style.textTransform === "lowercase") text = text.toLowerCase();
        const size = parseFloat(style.fontSize) / PITCH;
        const font = `${style.fontStyle} ${style.fontWeight} ${size}px ${style.fontFamily}`;
        for (const rect of rects) {
          if (rect.width < 4 || rect.height < 4) continue;
          const cw = Math.ceil(rect.width / PITCH);
          const ch = Math.ceil(rect.height / PITCH);
          scratch.width = cw;
          scratch.height = ch;
          ctx.clearRect(0, 0, cw, ch);
          ctx.font = font;
          ctx.textBaseline = "middle";
          ctx.fillStyle = "#000";
          ctx.fillText(text, 0, ch / 2);
          const data = ctx.getImageData(0, 0, cw, ch).data;
          const cells = [];
          for (let j = 0; j < ch; j++) {
            for (let i = 0; i < cw; i++) {
              if (data[(j * cw + i) * 4 + 3] > INK_ALPHA) cells.push(i, j);
            }
          }
          addRun(rect.left + sx, rect.top + sy, rect.width, rect.height, cells);
        }
      }
    }
    // Specks are drawn from runs in proportion to their ink, so a short
    // navbar word sheds no more than its share and the big title most.
    let total = 0;
    for (const run of runs) total += run.cells.length;
    this.runs = runs;
    this.totalCells = total;
  }

  pickRun() {
    let pick = Math.random() * this.totalCells;
    for (const run of this.runs) {
      pick -= run.cells.length;
      if (pick <= 0) return run;
    }
    return this.runs[this.runs.length - 1];
  }

  start() {
    if (this.frame) return;
    this.ensureCanvas();
    if (!this.runs) this.rasterize();
    this.canvas.style.display = "";
    this.last = performance.now();
    this.lastR = this.r;
    const tick = (now) => {
      this.frame = requestAnimationFrame(tick);
      const dt = Math.min((now - this.last) / 1000, 0.05);
      this.last = now;
      this.step(dt);
      this.paint();
      if (this.r <= 0 && this.loose.length === 0) this.stop();
    };
    this.frame = requestAnimationFrame(tick);
  }

  stop() {
    if (this.frame) cancelAnimationFrame(this.frame);
    this.frame = null;
    this.loose.length = 0;
    if (this.canvas) {
      this.canvas.style.display = "none";
      this.canvas.width = 0;
      this.canvas.height = 0;
    }
  }

  destroy() {
    this.stop();
    this.unsubscribe();
    if (this.canvas) this.canvas.remove();
    this.canvas = null;
    this.ctx = null;
  }

  // How readily a glyph cell at distance `d` from the centre sheds a
  // speck: the edge's value in the band, tapering to the inner and outer
  // ends, nothing inside the circle or beyond the band.
  density(d) {
    const r = this.r;
    const band = this.band;
    if (d > r + band * BAND_OUT) return 0;
    if (d < r - band) return INSIDE_DENSITY;
    const t = d < r ? 1 - (r - d) / band : 1 - (d - r) / (band * BAND_OUT);
    return INSIDE_DENSITY + (EDGE_DENSITY - INSIDE_DENSITY) * Math.max(0, t);
  }

  // Loose cells leave glyphs that sit in the band.
  spawn(attempts) {
    const runs = this.runs;
    if (!runs || !runs.length) return;
    for (let i = 0; i < attempts && this.loose.length < MAX_LOOSE; i++) {
      const run = this.pickRun();
      const k = Math.floor(Math.random() * (run.cells.length / 2)) * 2;
      const x = run.x + run.cells[k] * PITCH;
      const y = run.y + run.cells[k + 1] * PITCH;
      const d = Math.hypot(x - this.x, y - this.y);
      if (Math.random() > this.density(d)) continue;
      const ux = (x - this.x) / (d || 1);
      const uy = (y - this.y) / (d || 1);
      const speed = SPECK_SPEED * (0.7 + Math.random() * 0.6);
      this.loose.push({
        x,
        y,
        vx: ux * speed,
        vy: uy * speed,
        // Sway across the direction of travel.
        sx: -uy,
        sy: ux,
        drift: 2 + Math.random() * 4,
        sway: 0.6 + Math.random() * 0.8,
        phase: Math.random() * Math.PI * 2,
        age: 0,
        life: SPECK_LIFE * (0.7 + Math.random() * 0.6),
        tone: Math.random() < 0.15 ? 2 : Math.random() < 0.6 ? 0 : 1,
      });
    }
  }

  step(dt) {
    const r = this.r;
    if (r > 0 && this.emit) {
      // Whole specks only: the fraction carries over to the next frame,
      // so a slow rate still emits evenly.
      const swept = Math.abs(r - this.lastR) * 2 * Math.PI * r;
      // No backlog past a frame: a fast move sheds its cap now and drops
      // the rest, so emission never keeps running after the move.
      this.emitAcc = Math.min(this.emitAcc + REST_RATE * dt + swept * SWEEP_RATE, MAX_SPAWN_PER_FRAME);
      const count = Math.floor(this.emitAcc);
      this.emitAcc -= count;
      this.spawn(count);
      this.gone = 0;
    } else {
      this.emitAcc = 0;
      this.gone += dt;
      if (this.gone >= GONE_FADE) this.loose.length = 0;
    }
    this.lastR = r;
    const live = [];
    for (const c of this.loose) {
      c.age += dt;
      if (c.age >= c.life) continue;
      const sway = Math.sin(c.age * c.sway + c.phase) * c.drift * dt;
      c.x += c.vx * dt + c.sx * sway;
      c.y += c.vy * dt + c.sy * sway;
      live.push(c);
    }
    this.loose = live;
  }

  paint() {
    const canvas = this.canvas;
    const ctx = this.ctx;
    const width = window.innerWidth;
    const height = window.innerHeight;
    const dpr = window.devicePixelRatio || 1;
    const pw = Math.round(width * dpr);
    const ph = Math.round(height * dpr);
    if (canvas.width !== pw || canvas.height !== ph) {
      canvas.width = pw;
      canvas.height = ph;
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, width, height);
    if (!this.inks) this.readInks();
    const sx = window.scrollX;
    const sy = window.scrollY;
    const inks = this.inks;
    for (const c of this.loose) {
      // In fast, out slowly (the globe's curve).
      const t = c.age / c.life;
      const fade = this.gone > 0 ? Math.max(0, 1 - this.gone / GONE_FADE) : 1;
      const alpha = Math.min(1, t / 0.12) * Math.pow(1 - t, 1.3) * this.speckOpacity * fade;
      if (alpha < 0.01) continue;
      ctx.fillStyle = inks[c.tone];
      ctx.globalAlpha = alpha;
      ctx.fillRect(Math.round(c.x - sx), Math.round(c.y - sy), PITCH, PITCH);
    }
    ctx.globalAlpha = 1;
  }
}
