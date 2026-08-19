// Scroll-triggered entrance for the "Built-in observability" card, drawn
// on a canvas overlay: one continuous eased sweep fills the whole
// distribution bar left to right, each segment lighting up as the
// frontier crosses its slot, preceded by a particle fade — a sparse cloud
// of 2px dither particles just ahead of the advancing edge, contained
// inside the bar's band, melting away with continuous alpha as the sweep
// passes through.
// The real DOM bar (always laid out at its final state) hides while the
// canvas plays and returns when the last block lands, so the end frame is
// pixel-identical to the static markup. The cacheable-targets count rolls
// up separately via CounterAnimation.
//
// Under reduced motion (or without JS) nothing plays and the chart shows
// its final frame.

const CELL = 4; // particle grid pitch
const DOT = 2; // 2px particles, the marketing dithers' dot size
const PAD = 8; // canvas margin so nothing clips at the bar's edges
const AHEAD = 56; // particle cloud reach ahead of the advancing edge
const RADIUS = 6; // the bar's corner radius
const DURATION = 1.6; // the full sweep across the bar, in seconds
const DISSOLVE = 0.25; // cloud fade-out after the sweep lands
const KEEP = 0.45; // fraction of grid cells that host a particle

// Deterministic hash in [0, 1): stable per cell, so each particle keeps
// its place and its own brightness while the edge sweeps past — the fade
// is continuous alpha, never pop-in/pop-out.
function noise2(x, y) {
  let h = (Math.imul(x + 1, 374761393) + Math.imul(y + 1, 668265263)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

export const CacheObservability = {
  mounted() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    this.raf = null;
    this.canvas = null;

    // Arm: hide the bar's segments from the start (like the minimal
    // overhead card's pre-state), so the chart never shows its finished
    // frame before the entrance plays.
    this.segEls = Array.from(this.el.querySelectorAll('[data-part="segment"]'));
    this.segEls.forEach((seg) => (seg.style.opacity = "0"));

    // Arm every value in the card at 0 (keeping its unit suffix); they
    // count up alongside the sweep when the card plays.
    this.counters = [];
    const valueEls = [
      this.el.querySelector('[data-part="heading"] strong'),
      ...this.el.querySelectorAll('[data-part="stat"] > [data-part="value"]'),
    ].filter(Boolean);
    for (const el of valueEls) {
      const match = el.textContent.trim().match(/^(\d+)(.*)$/);
      if (!match) continue;
      this.counters.push({ el, target: Number(match[1]), suffix: match[2] });
      el.textContent = `0${match[2]}`;
    }

    // Play only once the whole card (chart + copy) is in view, backing
    // the threshold off for viewports shorter than the card.
    const card = this.el.closest('[data-part="cell"]') || this.el;
    const threshold = card.offsetHeight > window.innerHeight * 0.9 ? 0.5 : 0.9;

    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          this.observer.disconnect();
          this.observer = null;
          this.play();
        }
      },
      { threshold },
    );
    this.observer.observe(card);
  },

  destroyed() {
    if (this.observer) this.observer.disconnect();
    if (this.raf !== null) cancelAnimationFrame(this.raf);
    this.cleanup();
  },

  cleanup() {
    if (this.segEls) this.segEls.forEach((seg) => (seg.style.opacity = ""));
    this.segEls = null;
    if (this.counters) this.counters.forEach((c) => (c.el.textContent = `${c.target}${c.suffix}`));
    this.counters = null;
    if (this.canvas) this.canvas.remove();
    this.canvas = null;
  },

  play() {
    const bar = this.el.querySelector('[data-part="bar"]');
    const panel = bar && bar.closest('[data-part="panel"]');
    if (!bar || !panel) return;

    // Geometry from the real (final-state) layout — the segments are only
    // opacity-hidden, so their boxes and computed colors still read true.
    const barRect = bar.getBoundingClientRect();
    const panelRect = panel.getBoundingClientRect();
    const segments = this.segEls.map((seg) => {
      const rect = seg.getBoundingClientRect();
      return {
        name: seg.dataset.segment,
        x: rect.left - barRect.left,
        w: rect.width,
        color: getComputedStyle(seg).backgroundColor,
      };
    });
    if (!segments.length || barRect.width === 0) {
      this.cleanup();
      return;
    }

    // The purple segments are too dark for the particles to read against
    // either surface, so the cloud uses the chart's punchiest purple —
    // the "uploaded" fill (brightest of the ramp in dark mode, darkest in
    // light). Only the failed segment keeps its own red.
    const uploaded = segments.find((seg) => seg.name === "uploaded");
    const particlePurple = (uploaded || segments[segments.length - 1]).color;

    const w = Math.ceil(barRect.width) + PAD * 2;
    const h = Math.ceil(barRect.height) + PAD * 2;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const canvas = document.createElement("canvas");
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    canvas.style.cssText =
      `position:absolute;left:${barRect.left - panelRect.left - PAD}px;` +
      `top:${barRect.top - panelRect.top - PAD}px;` +
      `width:${w}px;height:${h}px;pointer-events:none;`;
    if (getComputedStyle(panel).position === "static") panel.style.position = "relative";
    panel.appendChild(canvas);
    this.canvas = canvas;

    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const barW = barRect.width;
    const barH = barRect.height;

    // One continuous sweep: a single eased frontier crosses the whole
    // bar, filling each segment as it passes — no per-segment stages.
    const lastEnd = DURATION;
    const totalT = lastEnd + DISSOLVE;
    const easeOut = (p) => 1 - Math.pow(1 - p, 3);
    let start = null;

    const frame = (now) => {
      if (start === null) start = now;
      const t = (now - start) / 1000;

      const p = easeOut(Math.min(1, t / DURATION));
      const frontier = p * barW;

      // Every value in the card counts up in lockstep with the sweep.
      if (this.counters) {
        for (const c of this.counters) {
          c.el.textContent = `${Math.round(p * c.target)}${c.suffix}`;
        }
      }
      // The particle cloud is the fixed bright purple except while the
      // frontier sweeps the failed segment, where it goes red.
      let activeColor = particlePurple;
      for (let i = segments.length - 1; i >= 0; i--) {
        if (frontier >= segments[i].x) {
          if (segments[i].name === "failed") activeColor = segments[i].color;
          break;
        }
      }

      ctx.clearRect(0, 0, w, h);

      // Solid fills behind the frontier, clipped to the bar's rounded
      // outline.
      ctx.save();
      ctx.beginPath();
      ctx.roundRect(PAD, PAD, barW, barH, RADIUS);
      ctx.clip();
      for (const seg of segments) {
        const filled = Math.min(seg.w, frontier - seg.x);
        if (filled <= 0) continue;
        ctx.fillStyle = seg.color;
        ctx.fillRect(PAD + seg.x, PAD, filled, barH);
      }
      ctx.restore();

      // Particle fade: a sparse cloud of 2px particles just ahead of the
      // advancing edge, contained inside the bar's band and colored like
      // the active block. Each particle's alpha falls off continuously
      // with distance from the edge (and each keeps its own brightness
      // from its stable hash), so the cloud melts smoothly instead of
      // popping. After the last block lands the cloud fades out.
      const fade = t <= lastEnd ? 1 : Math.max(0, 1 - (t - lastEnd) / DISSOLVE);
      if (fade > 0 && frontier < barW) {
        const gy0 = Math.ceil(PAD / CELL);
        const gy1 = Math.floor((PAD + barH - DOT) / CELL);
        const gx0 = Math.max(Math.ceil(PAD / CELL), Math.floor((PAD + frontier) / CELL));
        const gx1 = Math.min(Math.floor((PAD + barW - DOT) / CELL), Math.ceil((PAD + frontier + AHEAD) / CELL));
        ctx.fillStyle = activeColor;
        for (let gy = gy0; gy <= gy1; gy++) {
          for (let gx = gx0; gx <= gx1; gx++) {
            const n = noise2(gx, gy);
            if (n >= KEEP) continue;
            const cx = gx * CELL;
            const d = cx - (PAD + frontier);
            if (d < 0) continue;
            const alpha = Math.exp(-d / (AHEAD * 0.35)) * (0.3 + (n / KEEP) * 0.7) * fade;
            if (alpha < 0.02) continue;
            ctx.globalAlpha = Math.min(1, alpha);
            ctx.fillRect(cx, gy * CELL, DOT, DOT);
          }
        }
        ctx.globalAlpha = 1;
      }

      if (t >= totalT) {
        this.raf = null;
        this.cleanup();
        return;
      }
      this.raf = requestAnimationFrame(frame);
    };
    this.raf = requestAnimationFrame(frame);
  },
};
