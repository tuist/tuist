/*
 * Compute hero background — the blueprint mosaic: a gap-free tiling of
 * 40/80/120/160px squares on a 40px lattice, each square carrying a 10px
 * round dot tucked into its top-right corner (5px off both borders).
 * The square strokes draw on the illustrations' neutral-4, the dots one
 * step down on neutral-3, and a rotating handful of dots glow purple-400
 * and flicker as they change — runners lighting up.
 *
 * The tiling is deterministic, not random: a fixed-seed PRNG drives the
 * greedy row-major fill (first free lattice cell gets a weighted-size
 * square that overlaps nothing and fits fully in-bounds), so a given hero
 * size always lays out the same mosaic with every square whole — nothing
 * clips at the edges. The lattice itself stretches a hair so it divides
 * the hero exactly (cols = round(width / 40), cell = width / cols), which
 * is what lets arbitrary hero widths tile edge to edge without cut
 * squares or remainder gaps. Only the runtime churn of which dots are
 * purple is random, matching the runner-grid illustration's cadence.
 *
 * Under reduced motion the mosaic still draws, with its seeded purple dots
 * frozen — no churn, no flicker.
 */

import { onThemeChange } from "../lib/theme.js";

const CELL = 40;
const SIZES = [4, 3, 2, 1]; // lattice cells: 160, 120, 80, 40
// Minimal look: mostly 160s and 120s, the 40s only as rare accents or
// forced closers where nothing else fits.
const WEIGHTS = { 1: 0.04, 2: 0.29, 3: 0.22, 4: 0.45 };
// The deliberate 40s: an 80 occasionally shatters into a 2x2 cluster of
// them — the comp's look — which keeps them inside an 80 footprint where
// they can't notch the lattice into forced ribbons.
const SPLIT_CHANCE = 0.2;
const DOT_RADIUS = 5; // 10x10 dot
const DOT_INSET = 5; // gap between the dot's box and the square's border
const PURPLE_SHARE = 0.1; // of all squares, roughly
const SWAP_MS = 2600; // how often the purple set churns
const FLICKER_MS = 950; // flicker-in / flicker-out transition
const TICK_HZ = 18; // quantized redraw — the site's "digital" cadence
const SEED = 0x7061c3;
// Entrance wave: on page load a purple front sweeps the card from the
// bottom-left corner to the top-right, pulsing every dot as it passes —
// then, once the wave has fully faded, the seeded runner dots flicker in
// with a loose stagger and stay lit. Churn waits for all of it.
const WAVE_DELAY_MS = 400; // after mount, before the front launches
const WAVE_MS = 1400; // the front's crossing time
const WAVE_RISE_MS = 150; // per-dot attack as the front arrives
const WAVE_TAIL_MS = 550; // per-dot decay after the front passes
const LIGHT_DELAY_MS = 250; // breath between the faded wave and the runners
const LIGHT_STAGGER_MS = 700; // the runners come online loosely, not in a row

// Deterministic PRNG for the layout (and the initial purple set), so the
// mosaic is identical on every load.
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
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

export const ComputeHeroGrid = {
  mounted() {
    this.canvas = this.el.querySelector("canvas");
    if (!this.canvas) return;
    this.ctx = this.canvas.getContext("2d");
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    this.resolveColors = () => {
      this.cStroke = resolveTokenColor(this.el, "--marketing-illustration-neutral-4");
      this.cNeutral = resolveTokenColor(this.el, "--marketing-illustration-neutral-3");
      this.cPurple = resolveTokenColor(this.el, "--noora-purple-400");
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.paintStrokes();
      this.render(this.lastNow || 0);
    });

    // The lattice only changes on resize or theme flips, so its strokes
    // are prerendered here once and blitted per tick instead of
    // re-rasterizing every rect path at the animation cadence.
    this.strokeLayer = document.createElement("canvas");

    this.squares = [];
    this.resize = () => {
      const rect = this.canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.dpr = dpr;
      this.layout();
      this.paintStrokes();
      this.render(this.lastNow || 0);
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.canvas);
    this.resize();

    if (this.reduced) return;

    this.lastSwap = 0;
    this.lastTick = -1;
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      if (this.canvas.checkVisibility && !this.canvas.checkVisibility()) return;
      const step = Math.floor((now / 1000) * TICK_HZ);
      if (step === this.lastTick) return;
      this.lastTick = step;
      this.lastNow = now;
      if (this.waveStart == null) {
        this.waveStart = now + WAVE_DELAY_MS;
        this.armWaveArrivals();
      }
      if (
        !this.waveDone &&
        now > this.waveStart + WAVE_MS + WAVE_TAIL_MS + LIGHT_DELAY_MS + LIGHT_STAGGER_MS + FLICKER_MS
      ) {
        this.waveDone = true;
        // A calm settle: the first churn waits a full SWAP_MS after the
        // wave instead of firing on its heels.
        this.lastSwap = now;
      }
      this.update(now);
      this.render(now);
    };
    this.raf = requestAnimationFrame(tick);
  },

  // A dot's position along the wave's axis, 0..1 from the bottom-left
  // corner of the card to the top-right.
  waveFrac(sq) {
    return (sq.cx + (this.h - sq.cy)) / (this.w + this.h);
  },

  // The seeded active dots light up only after the wave has fully passed:
  // the front sweeps clean, and once it fades the runners come online in
  // a loose per-dot stagger.
  armWaveArrivals() {
    const settle = this.waveStart + WAVE_MS + WAVE_TAIL_MS + LIGHT_DELAY_MS;
    for (const sq of this.squares) {
      if (sq.active) sq.changeAt = settle + sq.seed * LIGHT_STAGGER_MS;
    }
  },

  // Transient pulse as the front passes a dot: a quick rise at arrival,
  // then an exponential decay back to neutral behind the front.
  waveLevel(sq, now) {
    if (this.reduced || this.waveDone || this.waveStart == null) return 0;
    const lagMs = (now - this.waveStart) - this.waveFrac(sq) * WAVE_MS;
    if (lagMs <= 0) return 0;
    const rise = Math.min(1, lagMs / WAVE_RISE_MS);
    const decay = Math.exp(-Math.max(0, lagMs - WAVE_RISE_MS) / WAVE_TAIL_MS);
    const level = rise * decay;
    return level < 0.01 ? 0 : level;
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.observer) this.observer.disconnect();
  },

  // Gap-free greedy tiling: scan the lattice row-major; every first free
  // cell anchors a square whose size is a seeded weighted pick among the
  // sizes that overlap nothing already placed AND sit fully in-bounds —
  // squares are never cut by the hero's edges. A 1-cell square always
  // fits, so no cell is ever left bare, and the lattice divides the hero
  // exactly, so the last row/column closes flush with the edge.
  layout() {
    const cols = Math.max(1, Math.round(this.w / CELL));
    const rows = Math.max(1, Math.round(this.h / CELL));
    const cellW = this.w / cols;
    const cellH = this.h / rows;
    const rand = mulberry32(SEED);
    const occupied = new Uint8Array(cols * rows);
    const squares = [];

    const place = (r, c, size) => {
      for (let dr = 0; dr < size; dr++) {
        for (let dc = 0; dc < size; dc++) {
          occupied[(r + dr) * cols + (c + dc)] = 1;
        }
      }
      // Pixel edges snap per lattice line, so neighbours share the same
      // rounded edge: crisp 1px strokes, exact coverage, no seams.
      const x0 = Math.round(c * cellW);
      const y0 = Math.round(r * cellH);
      const x1 = Math.round((c + size) * cellW);
      const y1 = Math.round((r + size) * cellH);
      squares.push({
        x0,
        y0,
        x1,
        y1,
        // The corner dot's center, fixed at layout so the per-tick paint
        // and the wave math don't re-derive it.
        cx: x1 - DOT_INSET - DOT_RADIUS,
        cy: y0 + DOT_INSET + DOT_RADIUS,
        active: false,
        changeAt: -9999,
        seed: rand(),
      });
    };

    // The four corners anchor with the biggest square, so the mosaic
    // frames the card with 160s instead of whatever the scan happens to
    // reach the edges with.
    const big = SIZES[0];
    if (cols >= 2 * big && rows >= 2 * big) {
      place(0, 0, big);
      place(0, cols - big, big);
      place(rows - big, 0, big);
      place(rows - big, cols - big, big);
    }

    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        if (occupied[r * cols + c]) continue;

        const fits = SIZES.filter((s) => {
          if (r + s > rows || c + s > cols) return false;
          for (let dr = 0; dr < s; dr++) {
            for (let dc = 0; dc < s; dc++) {
              if (occupied[(r + dr) * cols + (c + dc)]) return false;
            }
          }
          return true;
        });

        // Never leave a single-cell sliver — against an edge or against an
        // already-placed square. Those slivers are what the fill can only
        // patch with ribbons of 40s, so sizes that would create one are
        // ruled out while any other choice exists. freeRun measures the
        // free strip the placement would leave beside/below itself: 0 is
        // flush (fine), 1 is a sliver (avoid), 2+ leaves room for an 80+.
        const freeRun = (rr, cc, dr, dc) => {
          let n = 0;
          while (rr >= 0 && rr < rows && cc >= 0 && cc < cols && !occupied[rr * cols + cc]) {
            n++;
            rr += dr;
            cc += dc;
          }
          return n;
        };
        let candidates = fits.filter((s) => freeRun(r, c + s, 0, 1) !== 1 && freeRun(r + s, c, 1, 0) !== 1);
        if (!candidates.length) candidates = fits;
        // 40s are patch material, not part of the look: never pick one
        // while anything bigger can go here — a stray 40 in open space
        // notches the lattice and forces a whole ribbon of them.
        if (candidates.length > 1) candidates = candidates.filter((s) => s !== 1);

        const total = candidates.reduce((sum, s) => sum + WEIGHTS[s], 0);
        let roll = rand() * total;
        let size = candidates[candidates.length - 1];
        for (const s of candidates) {
          roll -= WEIGHTS[s];
          if (roll <= 0) {
            size = s;
            break;
          }
        }

        if (size === 2 && rand() < SPLIT_CHANCE) {
          place(r, c, 1);
          place(r, c + 1, 1);
          place(r + 1, c, 1);
          place(r + 1, c + 1, 1);
        } else {
          place(r, c, size);
        }
      }
    }

    this.squares = squares;
    this.purpleTarget = Math.max(4, Math.round(squares.length * PURPLE_SHARE));

    // The purple lives on the right of the card, away from the hero copy:
    // a square's chance of lighting up ramps quadratically with its
    // horizontal position, leaving just a whisper of weight on the left.
    for (const sq of squares) {
      const nx = (sq.x0 + sq.x1) / 2 / this.w;
      sq.bias = 0.03 + 0.97 * Math.pow(Math.max(0, (nx - 0.3) / 0.7), 2);
    }

    // Seeded initial purple set. Under reduced motion (or once the wave
    // has run) it sits settled from the first frame; while the entrance
    // wave is pending, the actives wait unlit (changeAt in the future)
    // until the front reaches them.
    const pool = [...squares];
    for (let i = 0; i < this.purpleTarget && pool.length; i++) {
      const sq = this.pickWeighted(pool, rand);
      sq.active = true;
      pool.splice(pool.indexOf(sq), 1);
    }
    if (!this.reduced && !this.waveDone) {
      if (this.waveStart != null) {
        this.armWaveArrivals();
      } else {
        for (const sq of squares) {
          if (sq.active) sq.changeAt = Number.POSITIVE_INFINITY;
        }
      }
    }
  },

  // Roulette pick over each square's positional bias.
  pickWeighted(list, randFn) {
    const total = list.reduce((sum, sq) => sum + sq.bias, 0);
    let roll = randFn() * total;
    for (const sq of list) {
      roll -= sq.bias;
      if (roll <= 0) return sq;
    }
    return list[list.length - 1];
  },

  rgba([r, g, b], a) {
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  },

  lerp(a, b, t) {
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  },

  // Churn the purple set gently around its target, one flickered change at
  // a time — the runner-grid recipe. Holds off until the entrance wave
  // has fully settled.
  update(now) {
    if (!this.waveDone) return;
    if (now - this.lastSwap < SWAP_MS) return;
    const settled = (sq) => now - sq.changeAt >= FLICKER_MS;
    const active = this.squares.filter((sq) => sq.active && settled(sq));
    const idle = this.squares.filter((sq) => !sq.active && settled(sq));
    const count = this.squares.filter((sq) => sq.active).length;

    let act, deact;
    const r = Math.random();
    if (count <= this.purpleTarget - 3) [act, deact] = [true, false];
    else if (count >= this.purpleTarget + 3) [act, deact] = [false, true];
    else if (r < 0.35) [act, deact] = [true, false];
    else if (r < 0.7) [act, deact] = [false, true];
    else [act, deact] = [true, true]; // swap

    let changed = false;
    if (deact && active.length) {
      const sq = active[Math.floor(Math.random() * active.length)];
      sq.active = false;
      sq.changeAt = now;
      changed = true;
    }
    if (act && idle.length) {
      // Same right-side bias as the initial set, so the churn keeps the
      // purple where it was seeded.
      const sq = this.pickWeighted(idle, Math.random);
      sq.active = true;
      sq.changeAt = now;
      changed = true;
    }
    if (changed) this.lastSwap = now;
  },

  // Purple level 0..1 for a dot: a flicker envelope while transitioning,
  // then a settled soft pulse (purple) or 0 (neutral).
  dotLevel(sq, now) {
    const age = now - sq.changeAt;
    // Not lit yet (a wave arrival still ahead — possibly Infinity while
    // the wave is unscheduled, which the math below would NaN on).
    if (age < 0) return 0;
    if (age >= FLICKER_MS) {
      return sq.active ? 0.75 + 0.25 * Math.sin(now * 0.004 + sq.seed * 10) : 0;
    }
    const p = age / FLICKER_MS;
    const env = sq.active ? p : 1 - p;
    const flick = 0.62 + 0.38 * Math.sin(p * Math.PI * 3 + sq.seed * 6);
    return Math.max(0, env * flick);
  },

  // Rasterize the lattice strokes into the offscreen layer. Runs on
  // resize and theme change only.
  paintStrokes() {
    this.strokeLayer.width = this.canvas.width;
    this.strokeLayer.height = this.canvas.height;
    const ctx = this.strokeLayer.getContext("2d");
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.lineWidth = 1;
    ctx.strokeStyle = this.rgba(this.cStroke, 1);
    for (const sq of this.squares) {
      // Strokes lying on the canvas perimeter are pushed one pixel out so
      // they clip away — the card's own border is the mosaic's outer
      // frame, and drawing it again just inside read as a double line.
      // +0.5: the edges are whole pixels, so the 1px stroke sits crisply
      // on the shared lines between squares.
      const x0 = sq.x0 === 0 ? -1 : sq.x0;
      const y0 = sq.y0 === 0 ? -1 : sq.y0;
      const x1 = sq.x1 === this.w ? this.w + 1 : sq.x1;
      const y1 = sq.y1 === this.h ? this.h + 1 : sq.y1;
      ctx.strokeRect(x0 + 0.5, y0 + 0.5, x1 - x0, y1 - y0);
    }
  },

  render(now) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.w, this.h);
    ctx.drawImage(this.strokeLayer, 0, 0, this.w, this.h);

    // Idle dots — most of them, most of the time — batch into a single
    // path and one fill; only dots carrying purple pay an individual
    // fillStyle + fill.
    const neutral = new Path2D();
    let hasNeutral = false;
    for (const sq of this.squares) {
      const level = Math.max(this.dotLevel(sq, now), this.waveLevel(sq, now));
      if (level > 0) {
        ctx.fillStyle = this.rgba(this.lerp(this.cNeutral, this.cPurple, level), 1);
        ctx.beginPath();
        ctx.arc(sq.cx, sq.cy, DOT_RADIUS, 0, Math.PI * 2);
        ctx.fill();
      } else {
        neutral.moveTo(sq.cx + DOT_RADIUS, sq.cy);
        neutral.arc(sq.cx, sq.cy, DOT_RADIUS, 0, Math.PI * 2);
        hasNeutral = true;
      }
    }
    if (hasNeutral) {
      ctx.fillStyle = this.rgba(this.cNeutral, 1);
      ctx.fill(neutral);
    }
  },
};
