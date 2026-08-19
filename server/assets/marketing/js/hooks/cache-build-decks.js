// Click-to-cycle deck for the build-system blueprint cards: clicking the
// front panel sends it to the back and brings the next system forward.
// CSS owns the slot positions and the swap transition via data-pos; this
// hook rotates the attribute and draws the front card's hover dither — a
// rim of purple dots INSIDE the card, hugging its edges and dissolving
// toward the middle (color from --marketing-cache-build-halo, re-resolved
// on theme change). The rim is torch-lit: only a small pool around the
// pointer shows, trailing the cursor like a flashlight in the dark, and
// it fades in with the CSS purple glow while the front card is hovered.

import { onThemeChange } from "../lib/theme.js";

const PITCH = 2; // full 2px dots on the 2px cell grid, like the dividers
const REACH = 20; // how far the rim reaches into the card
const TORCH = 55; // the pointer's light pool radius over the rim
const SWAP_MS = 600; // keep redrawing while the CSS position swap runs

// Ordered 8x8 Bayer matrix — the page dividers' threshold pattern
// (dither-texture.js). The rim's torch-lit signal reads through it, so
// the lit patch is the dividers' evenly-woven grain.
// Deterministic hash in [0, 1): stable per cell — picks which cells host
// the bright accent dots so they never reshuffle between frames.
function noise2(x, y) {
  let h = (Math.imul(x + 1, 374761393) + Math.imul(y + 1, 668265263)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

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
  return resolved;
}

export const CacheBuildDecks = {
  mounted() {
    this.panels = Array.from(this.el.querySelectorAll('[data-part="panel"]'));
    this.panels.forEach((panel, index) => panel.setAttribute("data-pos", index));
    this.raf = null;
    this.glow = 0;
    this.hovered = false;
    this.swapUntil = 0;
    // Target and eased pointer position — the torch trails the cursor.
    this.tx = null;
    this.ty = null;
    this.px = null;
    this.py = null;

    // The rim canvas paints above the front card (same z, later sibling),
    // but only inside its rect — pointer-events stay off so hover and
    // clicks reach the card.
    this.canvas = document.createElement("canvas");
    this.canvas.style.cssText =
      "position:absolute;inset:0;width:100%;height:100%;pointer-events:none;z-index:var(--noora-z-index-1);";
    this.el.appendChild(this.canvas);
    this.ctx = this.canvas.getContext("2d");

    this.resolveColor = () => {
      this.haloColor = resolveTokenColor(this.el, "--marketing-cache-build-halo");
      this.accentColor = resolveTokenColor(this.el, "--marketing-cache-build-halo-accent");
    };
    this.resolveColor();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColor();
      this.draw();
    });

    this.resize = () => {
      const rect = this.el.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.draw();
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.el);
    this.resize();

    // Hover state via delegation, so it keeps working as the front card
    // changes identity.
    this.onMouseOver = (event) => {
      this.setHovered(!!event.target.closest('[data-part="panel"][data-pos="0"]'));
    };
    this.onMouseLeave = () => this.setHovered(false);
    this.onMouseMove = (event) => {
      const rect = this.el.getBoundingClientRect();
      this.tx = event.clientX - rect.left;
      this.ty = event.clientY - rect.top;
      this.ensureLoop();
    };
    this.el.addEventListener("mouseover", this.onMouseOver);
    this.el.addEventListener("mouseleave", this.onMouseLeave);
    this.el.addEventListener("mousemove", this.onMouseMove);

    this.onClick = (event) => {
      const panel = event.target.closest('[data-part="panel"]');
      if (!panel || panel.getAttribute("data-pos") !== "0") return;
      for (const p of this.panels) {
        const pos = Number(p.getAttribute("data-pos"));
        p.setAttribute("data-pos", (pos + this.panels.length - 1) % this.panels.length);
      }
      this.swapUntil = performance.now() + SWAP_MS;
      this.ensureLoop();
    };
    this.el.addEventListener("click", this.onClick);
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.observer) this.observer.disconnect();
    if (this.raf !== null) cancelAnimationFrame(this.raf);
    this.el.removeEventListener("mouseover", this.onMouseOver);
    this.el.removeEventListener("mouseleave", this.onMouseLeave);
    this.el.removeEventListener("mousemove", this.onMouseMove);
    this.el.removeEventListener("click", this.onClick);
    if (this.canvas) this.canvas.remove();
  },

  setHovered(hovered) {
    if (this.hovered === hovered) return;
    this.hovered = hovered;
    this.ensureLoop();
  },

  // Runs while hovered (the torch follows the cursor), while the glow is
  // still fading, or while the swap transition plays.
  ensureLoop() {
    if (this.raf !== null) return;
    const tick = (now) => {
      const target = this.hovered ? 1 : 0;
      this.glow += (target - this.glow) * 0.15;
      if (Math.abs(target - this.glow) < 0.01) this.glow = target;
      if (this.tx !== null) {
        if (this.px === null) {
          this.px = this.tx;
          this.py = this.ty;
        } else {
          this.px += (this.tx - this.px) * 0.25;
          this.py += (this.ty - this.py) * 0.25;
        }
      }
      this.draw();
      if (this.hovered || this.glow !== target || now < this.swapUntil) {
        this.raf = requestAnimationFrame(tick);
      } else {
        this.raf = null;
      }
    };
    this.raf = requestAnimationFrame(tick);
  },

  draw() {
    const { ctx, w, h } = this;
    if (!ctx || !w) return;
    ctx.clearRect(0, 0, w, h);
    if (this.glow < 0.02 || this.px === null) return;
    const front = this.panels.find((p) => p.getAttribute("data-pos") === "0");
    if (!front) return;
    const hostRect = this.el.getBoundingClientRect();
    const rect = front.getBoundingClientRect();
    const x0 = rect.left - hostRect.left;
    const y0 = rect.top - hostRect.top;
    const x1 = x0 + rect.width;
    const y1 = y0 + rect.height;

    ctx.fillStyle = this.haloColor;
    const gx0 = Math.ceil(x0 / PITCH);
    const gx1 = Math.floor(x1 / PITCH);
    const gy0 = Math.ceil(y0 / PITCH);
    const gy1 = Math.floor(y1 / PITCH);
    for (let gy = gy0; gy <= gy1; gy++) {
      for (let gx = gx0; gx <= gx1; gx++) {
        const cx = gx * PITCH;
        const cy = gy * PITCH;
        // Distance from the nearest border, measured inward — the rim is
        // densest at the edges and dissolves toward the middle. The
        // bottom edge is excluded: it sits against the text block, and
        // lit dots there flash when the cursor crosses between cards.
        if (cy > y1) continue;
        const d = Math.min(cx - x0, x1 - cx, cy - y0);
        if (d < 0 || d > REACH) continue;
        // The torch: only the rim near the pointer lights up — a tight
        // gaussian pool, like a flashlight in the dark. The combined
        // signal (edge falloff x torch x glow) reads through the Bayer
        // threshold, so density does the shading like the dividers.
        const dist = Math.hypot(cx - this.px, cy - this.py);
        const torch = Math.exp(-((dist / TORCH) ** 2));
        const signal = Math.exp(-d / (REACH * 0.35)) * torch * this.glow * 0.95;
        const threshold = Math.max(BAYER8[(gy & 7) * 8 + (gx & 7)] / 64, 0.02);
        if (threshold >= signal) continue;
        // Most dots carry the dividers' soft grain weight; a sparse,
        // stable subset renders as full-strength accents (bright purple
        // in dark mode, deep purple in light) to make the hover pop.
        if (noise2(gx + 7, gy + 3) < 0.16) {
          ctx.fillStyle = this.accentColor;
          ctx.globalAlpha = Math.min(1, signal * 1.6);
          ctx.fillRect(cx, cy, PITCH, PITCH);
          ctx.fillStyle = this.haloColor;
        } else {
          ctx.globalAlpha = 0.35;
          ctx.fillRect(cx, cy, PITCH, PITCH);
        }
      }
    }
    ctx.globalAlpha = 1;
  },
};
