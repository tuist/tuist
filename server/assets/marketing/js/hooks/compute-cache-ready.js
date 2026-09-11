/*
 * "Cache-ready by default" scene animation, looped rounds:
 *   1. charge  — 1-3 random tiles light purple in persistent volume A
 *                (the round's artifacts); the cache pre-opens that many
 *                free slots, volume B opens one.
 *   2. deposit — a purple streak leaves volume A and rides the elbow
 *                slowly into the colocated cache...
 *   3. fill    — ...and the free slots fill in, one after another.
 *   4. serve   — after a beat, the pulse moves on along the other elbow
 *                into persistent volume B and fills its slot.
 *   5. hold    — everything stays lit, then melts slowly back to neutral
 *                and a fresh round begins elsewhere in the grids.
 *
 * Streaks draw on the pulses canvas 1:1 with whichever wires SVG the
 * breakpoint shows (paths read via getPointAtLength — the spark recipe).
 * The scene carries data-animated while the loop owns the tiles; without
 * JS or under reduced motion the comp's static purple tile shows instead.
 */

import { onThemeChange } from "../lib/theme.js";

const CHARGE_MS = 900;
const AMBIENT_TARGET_MIN = 5;
const AMBIENT_TARGET_SPAN = 3; // 5-7 tiles stay lit
const AMBIENT_SWAP_MS = 1500;
const DEPOSIT_MS = 1800;
const FILL_STAGGER_MS = 220;
const PAUSE_MS = 700;
const SERVE_MS = 1800;
const HOLD_MS = 2200;
const FADE_MS = 1000;
const IDLE_MS = 500;
const TRAIL = 34;
const STEPS = 6;

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

export const ComputeCacheReady = {
  mounted() {
    this.canvas = this.el.querySelector('[data-part="pulses"]');
    if (!this.canvas) return;
    this.ctx = this.canvas.getContext("2d");
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    this.runnerAName = this.el.querySelector('[data-node="runner-a"] [data-part="name"]');
    this.runnerBName = this.el.querySelector('[data-node="runner-b"] [data-part="name"]');
    this.jobA = 1042;
    this.jobB = 1057;
    this.rollTimers = [];
    this.sourceBlocks = Array.from(this.el.querySelectorAll('[data-node="volume-a"] [data-part="block"]'));
    this.cacheBlocks = Array.from(this.el.querySelectorAll('[data-node="cache"] [data-part="block"]'));
    this.volumeBlocks = Array.from(this.el.querySelectorAll('[data-node="volume-b"] [data-part="block"]'));

    this.rgb = resolveTokenColor(this.el, "--noora-purple-400");
    this.offThemeChange = onThemeChange(() => {
      this.rgb = resolveTokenColor(this.el, "--noora-purple-400");
    });

    this.mq = window.matchMedia("(max-width: 720px)");
    this.collectPaths = () => {
      const layout = this.mq.matches ? "mobile" : "desktop";
      const svg = this.el.querySelector(`svg[data-layout="${layout}"]`);
      const grab = (flow) => {
        const path = svg && svg.querySelector(`[data-flow="${flow}"]`);
        let len = 0;
        try {
          len = path ? path.getTotalLength() : 0;
        } catch {
          len = 0;
        }
        return { path, len };
      };
      this.deposit = grab("deposit");
      this.serve = grab("serve");
    };
    this.collectPaths();
    this.onMq = () => this.collectPaths();
    this.mq.addEventListener("change", this.onMq);

    this.resize = () => {
      const rect = this.canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.canvas);
    this.resize();

    if (this.reduced) return;

    // The loop owns the tiles from here (the comp's static purple tile
    // only shows without this attribute).
    this.el.setAttribute("data-animated", "");

    // The cache is always at work, not only when a round passes through:
    // a handful of tiles stay lit, membership drifting over time.
    this.ambient = [];
    for (const tile of this.pickMany(this.cacheBlocks, 6)) {
      tile.setAttribute("data-active", "");
      this.ambient.push(tile);
    }

    this.phase = "charge";
    this.phaseStart = null;
    this.nextAmbientAt = null;

    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      if (this.canvas.checkVisibility && !this.canvas.checkVisibility()) {
        this.phaseStart = null;
        this.nextAmbientAt = null;
        return;
      }
      if (this.nextAmbientAt == null) this.nextAmbientAt = now + AMBIENT_SWAP_MS;
      if (now >= this.nextAmbientAt) {
        this.churnAmbient();
        this.nextAmbientAt = now + AMBIENT_SWAP_MS * (0.7 + Math.random() * 0.8);
      }
      if (this.phaseStart == null) {
        this.phaseStart = now;
        this.phase = "charge";
        this.prepRound();
      }
      this.advance(now);
    };
    this.raf = requestAnimationFrame(tick);
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.observer) this.observer.disconnect();
    if (this.mq && this.onMq) this.mq.removeEventListener("change", this.onMq);
    if (this.rollTimers) this.rollTimers.forEach((id) => window.clearTimeout(id));
  },

  rgba(a) {
    const [r, g, b] = this.rgb;
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  },

  next(phase, now) {
    this.phase = phase;
    this.phaseStart = now;
  },

  advance(now) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.w, this.h);
    const t = now - this.phaseStart;

    if (this.phase === "charge") {
      if (t >= CHARGE_MS) this.next("deposit", now);
      return;
    }

    if (this.phase === "deposit") {
      this.drawStreak(this.deposit, Math.min(1, t / DEPOSIT_MS));
      if (t >= DEPOSIT_MS) {
        this.fillIndex = 0;
        this.next("fill-cache", now);
      }
      return;
    }

    if (this.phase === "fill-cache") {
      while (this.fillIndex < this.cacheHoles.length && t >= this.fillIndex * FILL_STAGGER_MS) {
        this.fill(this.cacheHoles[this.fillIndex]);
        this.fillIndex += 1;
      }
      if (t >= this.cacheHoles.length * FILL_STAGGER_MS + PAUSE_MS) this.next("serve", now);
      return;
    }

    if (this.phase === "serve") {
      this.drawStreak(this.serve, Math.min(1, t / SERVE_MS));
      if (t >= SERVE_MS) {
        this.fillIndex = 0;
        this.next("fill-volume", now);
      }
      return;
    }

    if (this.phase === "fill-volume") {
      while (this.fillIndex < this.volumeHoles.length && t >= this.fillIndex * FILL_STAGGER_MS) {
        this.fill(this.volumeHoles[this.fillIndex]);
        this.fillIndex += 1;
      }
      if (t >= this.volumeHoles.length * FILL_STAGGER_MS) this.next("hold", now);
      return;
    }

    if (this.phase === "hold") {
      if (t >= HOLD_MS) {
        // Everything melts back to neutral (the CSS transition carries
        // the slow fade) before the next round is drawn.
        this.unlightAll();
        this.next("fade", now);
      }
      return;
    }

    if (this.phase === "fade") {
      if (t >= FADE_MS) this.next("idle", now);
      return;
    }

    if (t >= IDLE_MS) {
      this.prepRound();
      this.next("charge", now);
    }
  },

  // A fresh round: everything neutral, then 1-3 artifacts light up in
  // volume A, the cache opens that many free slots, volume B opens one.
  prepRound() {
    for (const b of [...this.sourceBlocks, ...this.cacheBlocks, ...this.volumeBlocks]) {
      b.removeAttribute("data-lit");
      b.removeAttribute("data-empty");
    }
    // Fresh jobs land on both runners: the numbers roll (tabular digits
    // keep the lines steady).
    this.jobA += 1 + Math.floor(Math.random() * 3);
    this.jobB += 1 + Math.floor(Math.random() * 3);
    this.rollJob(this.runnerAName, "mac-m4-pro · job #", this.jobA);
    this.rollJob(this.runnerBName, "linux · job #", this.jobB);

    const count = 1 + Math.floor(Math.random() * 3);
    for (const tile of this.pickMany(this.sourceBlocks, count)) {
      tile.setAttribute("data-lit", "");
    }
    this.cacheHoles = this.pickMany(
      this.cacheBlocks.filter((b) => !b.hasAttribute("data-active")),
      count,
    );
    for (const tile of this.cacheHoles) tile.setAttribute("data-empty", "");
    // Volume B mirrors the round: the same number of slots open there
    // the moment the process starts.
    this.volumeHoles = this.pickMany(this.volumeBlocks, count);
    for (const tile of this.volumeHoles) tile.setAttribute("data-empty", "");
  },

  // Slot-roll only the job number — the machine name (digits included,
  // "m4") stays put; just the digits after the # churn before settling.
  rollJob(el, prefix, number) {
    if (!el) return;
    const digits = String(number);
    const start = performance.now();
    const timer = window.setInterval(() => {
      if (performance.now() - start >= 520) {
        el.textContent = prefix + digits;
        window.clearInterval(timer);
        return;
      }
      el.textContent = prefix + digits.replace(/[0-9]/g, () => Math.floor(Math.random() * 10));
    }, 60);
    // Interval and timeout ids share a namespace; destroyed() clears both.
    this.rollTimers.push(timer);
  },

  pickMany(blocks, count) {
    const candidates = blocks.filter((b) => (b.checkVisibility ? b.checkVisibility() : true));
    for (let i = candidates.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [candidates[i], candidates[j]] = [candidates[j], candidates[i]];
    }
    return candidates.slice(0, Math.min(count, candidates.length));
  },

  // Drift the ambient set: drop a member and/or light a fresh tile so
  // the count hovers in the 5-7 band and the pattern keeps changing.
  churnAmbient() {
    const target = AMBIENT_TARGET_MIN + Math.floor(Math.random() * AMBIENT_TARGET_SPAN);
    if (this.ambient.length && (this.ambient.length > target || Math.random() < 0.5)) {
      const i = Math.floor(Math.random() * this.ambient.length);
      this.ambient[i].removeAttribute("data-active");
      this.ambient.splice(i, 1);
    }
    if (this.ambient.length < target) {
      const free = this.cacheBlocks.filter(
        (b) =>
          !b.hasAttribute("data-active") &&
          !b.hasAttribute("data-lit") &&
          !b.hasAttribute("data-empty") &&
          (b.checkVisibility ? b.checkVisibility() : true),
      );
      if (free.length) {
        const tile = free[Math.floor(Math.random() * free.length)];
        tile.setAttribute("data-active", "");
        this.ambient.push(tile);
      }
    }
  },

  unlightAll() {
    for (const b of [...this.sourceBlocks, ...this.cacheBlocks, ...this.volumeBlocks]) {
      b.removeAttribute("data-lit");
    }
  },

  // The streak landed: the free slot fills in purple.
  fill(tile) {
    if (!tile) return;
    tile.removeAttribute("data-empty");
    tile.setAttribute("data-lit", "");
  },

  // One slow comet streak (transparent tail → bright head) along a wire;
  // eased so it leaves gently and lands gently.
  drawStreak(wire, progress) {
    if (!wire || !wire.path || !wire.len) return;
    const eased = progress * progress * (3 - 2 * progress);
    const head = wire.len * eased;
    const tail = Math.max(0, head - TRAIL);
    if (head <= 0) return;
    const ctx = this.ctx;
    const tp = wire.path.getPointAtLength(tail);
    const hp = wire.path.getPointAtLength(head);
    const grad = ctx.createLinearGradient(tp.x, tp.y, hp.x, hp.y);
    grad.addColorStop(0, this.rgba(0));
    grad.addColorStop(1, this.rgba(0.9));
    ctx.strokeStyle = grad;
    ctx.lineWidth = 1.5;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(tp.x, tp.y);
    for (let i = 1; i <= STEPS; i++) {
      const pt = wire.path.getPointAtLength(tail + ((head - tail) * i) / STEPS);
      ctx.lineTo(pt.x, pt.y);
    }
    ctx.stroke();
  },
};
