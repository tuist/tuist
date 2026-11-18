/*
 * An ordered-dither wave, drawn on a <canvas> that fills its parent: a
 * vertical density ramp bent by a slow drifting wave, turned into dots by an
 * 8x8 Bayer threshold. It's the marketing site's dither divider in a small
 * canvas-2D form: the canvas is one pixel per dither cell and is scaled up
 * with pixelated rendering, so a banner-sized strip costs a few thousand
 * cells per tick.
 *
 * Options (data attributes on the canvas):
 *   data-colors:     comma-separated custom property names for the dot color
 *                    ramp, shallow to deep, 2–4 entries (required)
 *   data-pitch:      dither cell size in CSS px (default 2)
 *   data-top:        density at the top edge, 0..1 (default 0)
 *   data-bottom:     density at the bottom edge, 0..1 (default 0.95)
 *   data-wave:       wave amplitude, 0 = plain ramp (default 0.335)
 *   data-wave-scale: wave frequency multiplier (default 2.5)
 *   data-speed:      drift speed multiplier, 0 = static (default 1)
 *   data-opacity:    dot opacity, 0..1 (default 0.3)
 *
 * The wave only moves while the canvas is on screen, holds still with
 * reduced motion, and re-reads its colors when the theme changes.
 */

const TICK_HZ = 16;

function number(dataset, key, fallback) {
  const value = Number(dataset[key]);
  return dataset[key] !== undefined && Number.isFinite(value)
    ? value
    : fallback;
}

// Threshold of the 8x8 Bayer matrix at a cell, 0..1.
function bayer8(x, y) {
  let value = 0;
  let weight = 16;
  for (let i = 0; i < 3; i++) {
    const bx = x & 1;
    const by = y & 1;
    value += (2 * ((bx + by) & 1) + by) * weight;
    weight /= 4;
    x >>= 1;
    y >>= 1;
  }
  return value / 64;
}

function smoothstep(edge0, edge1, x) {
  const t = Math.min(1, Math.max(0, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

export default {
  mounted() {
    const data = this.el.dataset;
    this.pitch = Math.max(1, number(data, "pitch", 2));
    this.top = number(data, "top", 0);
    this.bottom = number(data, "bottom", 0.95);
    this.wave = number(data, "wave", 0.335);
    this.waveScale = number(data, "waveScale", 2.5);
    this.speed = number(data, "speed", 1);
    this.opacity = number(data, "opacity", 0.3);
    this.tokens = (data.colors || "")
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean)
      .slice(0, 4);

    this.context = this.el.getContext ? this.el.getContext("2d") : null;
    if (!this.context || this.tokens.length < 2) return;

    this.el.style.imageRendering = "pixelated";
    this.reduced =
      window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    this.inView = true;
    this.lastTick = -1;

    this.readColors();
    this.resize();

    this.resizeObserver = new ResizeObserver(() => {
      this.resize();
      this.draw();
    });
    this.resizeObserver.observe(this.el);

    if ("IntersectionObserver" in window) {
      this.viewObserver = new IntersectionObserver(([entry]) => {
        this.inView = entry.isIntersecting;
      });
      this.viewObserver.observe(this.el);
    }

    // Colors are light-dark() tokens: re-read them when the theme switches,
    // through data-theme on <html> or the system preference.
    const recolor = () => {
      this.readColors();
      this.draw();
    };
    this.themeObserver = new MutationObserver(recolor);
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme", "class"],
    });
    this.schemeQuery = window.matchMedia?.("(prefers-color-scheme: dark)");
    this.schemeQuery?.addEventListener?.("change", recolor);
    this.recolor = recolor;

    this.draw();
    if (!this.reduced && this.speed > 0) {
      const tick = (now) => {
        this.frame = requestAnimationFrame(tick);
        if (!this.inView || document.hidden) return;
        const step = Math.floor((now / 1000) * TICK_HZ);
        if (step === this.lastTick) return;
        this.lastTick = step;
        this.draw(step / TICK_HZ);
      };
      this.frame = requestAnimationFrame(tick);
    }
  },

  destroyed() {
    cancelAnimationFrame(this.frame);
    this.resizeObserver?.disconnect();
    this.viewObserver?.disconnect();
    this.themeObserver?.disconnect();
    this.schemeQuery?.removeEventListener?.("change", this.recolor);
  },

  // Resolves each token to RGB through a hidden probe, so any color syntax
  // (oklch, light-dark) comes back as numbers.
  readColors() {
    const probe = document.createElement("span");
    probe.style.cssText = "position:absolute;visibility:hidden";
    this.el.parentElement.appendChild(probe);
    const scratch = document.createElement("canvas").getContext("2d");
    this.colors = this.tokens.map((token) => {
      probe.style.color = `var(${token})`;
      if (!scratch) return [128, 128, 128];
      scratch.clearRect(0, 0, 1, 1);
      scratch.fillStyle = getComputedStyle(probe).color;
      scratch.fillRect(0, 0, 1, 1);
      const [r, g, b] = scratch.getImageData(0, 0, 1, 1).data;
      return [r, g, b];
    });
    probe.remove();
  },

  resize() {
    const { width, height } = this.el.getBoundingClientRect();
    this.columns = Math.max(1, Math.ceil(width / this.pitch));
    this.rows = Math.max(1, Math.ceil(height / this.pitch));
    if (this.el.width !== this.columns || this.el.height !== this.rows) {
      this.el.width = this.columns;
      this.el.height = this.rows;
      this.image = this.context.createImageData(this.columns, this.rows);
    }
  },

  draw(seconds = performance.now() / 1000) {
    if (!this.image) return;
    const { columns, rows, colors, image } = this;
    const pixels = image.data;
    const t = seconds * 0.35 * this.speed;
    const alpha = Math.round(this.opacity * 255);
    const segments = colors.length - 1;

    for (let y = 0; y < rows; y++) {
      const v = (y + 0.5) / rows;
      const ramp = this.top + (this.bottom - this.top) * v;
      const slow = 0.15 * Math.sin(v * 6.7 * this.waveScale + t * 0.25);
      for (let x = 0; x < columns; x++) {
        const u = ((x + 0.5) / columns) * this.waveScale;
        const wave =
          0.55 * Math.sin(u * 5.1 - t * 0.5 + v * 1.8) +
          0.3 * Math.sin(u * 9.3 + t * 0.35 + 1.7) +
          slow;
        const density = Math.min(0.95, Math.max(0, ramp + this.wave * wave));
        const index = (y * columns + x) * 4;

        if (bayer8(x, y) >= density) {
          pixels[index + 3] = 0;
          continue;
        }

        const depth = smoothstep(0.35, 0.8, density) * segments;
        const base = Math.min(Math.floor(depth), segments - 1);
        const shade = base + (bayer8(x + 4, y + 4) < depth - base ? 1 : 0);
        const [r, g, b] = colors[shade];
        pixels[index] = r;
        pixels[index + 1] = g;
        pixels[index + 2] = b;
        pixels[index + 3] = alpha;
      }
    }

    this.context.putImageData(image, 0, 0);
  },
};
