/*
 * Compute illustration — the "ignition" animation, looped:
 *   1. pulse    — a purple line travels the lead line from the left into the
 *                 tuist logo hub.
 *   2. scan     — a vertical scan line sweeps rightward through the logo.
 *   3. transmit — purple packets travel the dashed fan lines from the logo out
 *                 to the runner cells (read straight off the SVG paths).
 *   4. idle     — pause, then repeat.
 *
 * Canvas overlay over the scene (1:1 with the wires SVG), layered above the
 * wires and below the logo hub.
 *
 * Options (data attributes, in SVG/scene px):
 *   data-lead:      lead-line length = logo left edge
 *   data-logo-size: logo box size
 *   data-cy:        vertical center of the lead line / logo
 */

import { onThemeChange } from "../lib/theme.js";

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

export const ComputeSpark = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const d = this.el.dataset;
    this.lead = Number(d.lead) || 181.25;
    this.logoSize = Number(d.logoSize) || 45;
    this.cyv = Number(d.cy) || 140; // cross-axis center of the lead line / logo
    this.vertical = d.orientation === "vertical";

    const host = this.canvas.parentElement;
    this.rgb = resolveTokenColor(host, "--noora-purple-400");
    this.offThemeChange = onThemeChange(() => {
      this.rgb = resolveTokenColor(host, "--noora-purple-400");
    });

    // Fan (logo → runner cells) and flow (runner cells → task panel) lines,
    // read straight from the SVG so packets ride them via getPointAtLength.
    const lengths = (sel) => {
      const paths = Array.from(host.querySelectorAll(sel));
      return [
        paths,
        paths.map((p) => {
          try {
            return p.getTotalLength();
          } catch {
            return 0;
          }
        }),
      ];
    };
    [this.fanPaths, this.fanLengths] = lengths('[data-part="wire-fan"]');
    [this.flowPaths, this.flowLengths] = lengths('[data-part="wire-flow"]');

    // Timing (ms).
    this.PULSE_MS = 850;
    this.SCAN_MS = 600;
    this.TRANSMIT_MS = 1100;
    this.IDLE_MS = 1200;

    this.resize = () => {
      const rect = this.canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.canvas);
    this.resize();

    this.phase = "pulse";
    this.phaseStart = null;
    // Continuous exit stream — independent of the enter cycle.
    this.flowPackets = [];
    this.nextFlowAt = null;

    if (this.reduced) return; // no animation for reduced-motion

    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      if (this.canvas.checkVisibility && !this.canvas.checkVisibility()) {
        this.phaseStart = null;
        this.nextFlowAt = null;
        return;
      }
      if (this.phaseStart == null) {
        this.phaseStart = now;
        this.phase = "pulse";
      }
      this.render(now);
    };
    this.raf = requestAnimationFrame(tick);
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.observer) this.observer.disconnect();
  },

  rgba(a) {
    const [r, g, b] = this.rgb;
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  },

  render(now) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.w, this.h);

    // Exit streaks run continuously, on their own timer — decoupled from the
    // enter cycle below, so results keep trickling out regardless of it.
    this.updateFlow(now);
    this.renderFlow(now);

    const t = now - this.phaseStart;

    if (this.phase === "pulse") {
      const p = Math.min(1, t / this.PULSE_MS);
      const m = p * p * (3 - 2 * p) * this.lead; // main-axis head position
      const c = this.cyv;
      const tailM = Math.max(0, m - 70);
      // Main axis is x (horizontal) or y (vertical); cross axis stays at c.
      const [hx, hy] = this.vertical ? [c, m] : [m, c];
      const [tx, ty] = this.vertical ? [c, tailM] : [tailM, c];
      const grad = ctx.createLinearGradient(tx, ty, hx, hy);
      grad.addColorStop(0, this.rgba(0));
      grad.addColorStop(1, this.rgba(0.6));
      ctx.strokeStyle = grad;
      ctx.lineWidth = 1.5;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(tx, ty);
      ctx.lineTo(hx, hy);
      ctx.stroke();
      if (p >= 1) this.next("scan", now);
      return;
    }

    if (this.phase === "scan") {
      this.renderScan(Math.min(1, t / this.SCAN_MS));
      if (t >= this.SCAN_MS) {
        this.fanPackets = this.spawnPackets(this.fanPaths.length, this.TRANSMIT_MS, 18);
        this.next("transmit", now);
      }
      return;
    }

    // Packets in to the runners (the enter burst for this cycle).
    if (this.phase === "transmit") {
      this.renderPackets(t, this.fanPaths, this.fanLengths, this.fanPackets);
      if (t >= this.TRANSMIT_MS) this.next("idle", now);
      return;
    }

    // idle
    if (t >= this.IDLE_MS) this.next("pulse", now);
  },

  next(phase, now) {
    this.phase = phase;
    this.phaseStart = now;
  },

  // Vertical scan line sweeping across the logo, clipped to its 45×45 box.
  // Just the line — no glow — fading in and out over the sweep.
  renderScan(p) {
    const ctx = this.ctx;
    const size = this.logoSize;
    // Logo box top-left: main axis starts at `lead`, cross axis centered on cyv.
    const bx = this.vertical ? this.cyv - size / 2 : this.lead;
    const by = this.vertical ? this.lead : this.cyv - size / 2;
    const env = Math.sin(p * Math.PI); // in → out

    ctx.save();
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(bx, by, size, size, 8);
    else ctx.rect(bx, by, size, size);
    ctx.clip();

    ctx.strokeStyle = this.rgba(0.85 * env);
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    if (this.vertical) {
      const sy = by + p * size; // horizontal line sweeping down
      ctx.moveTo(bx, sy);
      ctx.lineTo(bx + size, sy);
    } else {
      const sx = bx + p * size; // vertical line sweeping across
      ctx.moveTo(sx, by);
      ctx.lineTo(sx, by + size);
    }
    ctx.stroke();

    ctx.restore();
  },

  // A pool of packets randomly spread across `lineCount` lines (multiple per
  // line), each with its own start time + travel duration inside `windowMs`.
  spawnPackets(lineCount, windowMs, count) {
    const packets = [];
    if (!lineCount) return packets;
    for (let i = 0; i < count; i++) {
      const dur = 500 + Math.random() * 350;
      packets.push({
        line: Math.floor(Math.random() * lineCount),
        dur,
        t0: Math.random() * Math.max(0, windowMs - dur),
      });
    }
    return packets;
  },

  // One purple comet streak (transparent tail → bright head) at `pos` along a
  // path. Sampled as a short polyline so it hugs the curve instead of cutting
  // the corner on tight bends.
  drawStreak(path, pos) {
    const ctx = this.ctx;
    const TRAIL = 30;
    const STEPS = 5;
    const from = Math.max(0, pos - TRAIL);
    const tail = path.getPointAtLength(from);
    const head = path.getPointAtLength(pos);
    const grad = ctx.createLinearGradient(tail.x, tail.y, head.x, head.y);
    grad.addColorStop(0, this.rgba(0));
    grad.addColorStop(1, this.rgba(0.9));
    ctx.strokeStyle = grad;
    ctx.beginPath();
    ctx.moveTo(tail.x, tail.y);
    for (let i = 1; i <= STEPS; i++) {
      const pt = path.getPointAtLength(from + ((pos - from) * i) / STEPS);
      ctx.lineTo(pt.x, pt.y);
    }
    ctx.stroke();
  },

  // The fan (enter) packet pool, timed relative to the transmit phase.
  renderPackets(t, paths, lengths, packets) {
    if (!packets || !packets.length) return;
    this.ctx.lineWidth = 1.5;
    this.ctx.lineCap = "round";
    for (const pk of packets) {
      const local = (t - pk.t0) / pk.dur;
      if (local <= 0 || local >= 1) continue;
      const len = lengths[pk.line];
      if (len) this.drawStreak(paths[pk.line], local * len);
    }
  },

  // Continuous exit stream: spawn a flow streak every so often on its own clock,
  // drop finished ones. Independent of the enter cycle, so it never stops.
  updateFlow(now) {
    if (!this.flowPaths.length) return;
    this.flowPackets = this.flowPackets.filter((pk) => now < pk.t0 + pk.dur);
    if (this.nextFlowAt == null) this.nextFlowAt = now + 300;
    let guard = 0;
    while (now >= this.nextFlowAt && guard++ < 6) {
      this.flowPackets.push({
        line: Math.floor(Math.random() * this.flowPaths.length),
        t0: this.nextFlowAt,
        dur: 950 + Math.random() * 550,
      });
      this.nextFlowAt += 300 + Math.random() * 500; // gap between exits
    }
    if (now >= this.nextFlowAt) this.nextFlowAt = now; // stalled → resync
  },

  renderFlow(now) {
    if (!this.flowPackets.length) return;
    this.ctx.lineWidth = 1.5;
    this.ctx.lineCap = "round";
    for (const pk of this.flowPackets) {
      const local = (now - pk.t0) / pk.dur;
      if (local <= 0 || local >= 1) continue;
      const len = this.flowLengths[pk.line];
      if (len) this.drawStreak(this.flowPaths[pk.line], local * len);
    }
  },
};
