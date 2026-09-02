/**
 * FlakyQuarantine: the tests page's "Stop flakes from blocking CI" scene.
 *
 * Two cell grids on one canvas: the test suite on the left (12 rows, as
 * many columns as fit, up to the comp's 35) and the quarantine grid on the
 * right (7 x 12). Suite cells are empty, passed (purple) or flaky (yellow).
 * A crosshair sweeps to each flaky cell in turn, locks on, and the cell
 * flies over to the next free quarantine slot (filling from the bottom row
 * up, left to right). New flakes keep surfacing in the suite so the sweep
 * never ends, and the quarantine grid holds at most five rows: when a sixth
 * would start, the whole stack shifts down a row and the oldest row drops
 * off the bottom.
 *
 * Colours come from --flaky-* custom properties on the host figure
 * (light-dark() colours), resolved through a probe element and re-resolved
 * on a runtime theme flip. The "Quarantined tests" label is a DOM element
 * the hook positions over the quarantine grid. The loop only runs while
 * the canvas is on screen; reduced motion paints one static frame with
 * the crosshair locked on a flake.
 */
import { onThemeChange } from "../lib/theme.js";

const CELL = 15;
const GAP = 8;
const PITCH = CELL + GAP;
const RADIUS = 2;
const CORE_INSET = 3; // the flake's solid core sits this far inside its cell
const ROWS = 12;
const MAX_COLS = 35;
const QUARANTINE_COLS = 7;
const GRID_GAP = 24; // between the suite and the quarantine grid
const MIN_INSET = 24;
const LABEL_GAP = 12;

const PASS_RATIO = 0.36;
const FLAKY_COUNT = 12;
const PREQUARANTINED = 14; // two full bottom rows at rest
const MAX_QUARANTINE_ROWS = 5;
const MAX_PENDING = 10; // stop spawning flakes while this many await the crosshair

// Phase durations (ms).
const MOVE_MS = 450;
const HOLD_MS = 350;
const FLY_MS = 550;
const BETWEEN_MS = 250;
const SHIFT_MS = 400;
const SPAWN_MIN_MS = 1100;
const SPAWN_MAX_MS = 2200;

const COLORS = [
  "empty",
  "pass-stroke",
  "pass-fill",
  "flaky-stroke",
  "flaky-fill",
  "flaky-core",
  "quarantine-stroke",
  "quarantine-fill",
  "crosshair",
];

function easeInOut(t) {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}

function resolveColor(host, name) {
  const probe = document.createElement("span");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.color = `var(${name})`;
  host.appendChild(probe);
  const color = getComputedStyle(probe).color;
  probe.remove();
  return color;
}

const FlakyQuarantine = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.closest("figure") || this.canvas.parentElement;
    this.label = this.host.querySelector('[data-part="label"]');
    this.frame = null;
    this.lastTime = null;
    this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.colors = {};
    this.cols = 0;

    this.resizeObserver = new ResizeObserver(() => {
      this.resize();
      this.draw();
    });
    this.resizeObserver.observe(this.canvas);
    this.resize();
    this.draw();

    this.intersectionObserver = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        this.start();
      } else {
        this.stop();
      }
    });
    this.intersectionObserver.observe(this.canvas);

    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.draw();
    });
  },

  destroyed() {
    this.stop();
    this.offThemeChange?.();
    this.resizeObserver?.disconnect();
    this.intersectionObserver?.disconnect();
  },

  resolveColors() {
    for (const name of COLORS) {
      this.colors[name] = resolveColor(this.host, `--flaky-${name}`);
    }
  },

  resize() {
    const dpr = window.devicePixelRatio || 1;
    const rect = this.canvas.getBoundingClientRect();
    this.width = rect.width;
    this.height = rect.height;
    const w = Math.round(rect.width * dpr);
    const h = Math.round(rect.height * dpr);
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.resolveColors();
    this.layout();
  },

  // Fit as many suite columns as the width allows (up to the comp's 35),
  // then centre both grids as one block.
  layout() {
    const quarantineWidth = QUARANTINE_COLS * PITCH - GAP;
    const available = this.width - 2 * MIN_INSET - GRID_GAP - quarantineWidth;
    const cols = Math.max(4, Math.min(MAX_COLS, Math.floor((available + GAP) / PITCH)));
    const suiteWidth = cols * PITCH - GAP;
    const gridHeight = ROWS * PITCH - GAP;
    const total = suiteWidth + GRID_GAP + quarantineWidth;
    const left = Math.round((this.width - total) / 2);
    const top = Math.round((this.height - gridHeight) / 2);

    this.suite = { x: left, y: top, cols, width: suiteWidth, height: gridHeight };
    this.quarantine = { x: left + suiteWidth + GRID_GAP, y: top, cols: QUARANTINE_COLS, width: quarantineWidth };

    if (this.label) {
      this.label.style.left = `${this.quarantine.x}px`;
      this.label.style.width = `${quarantineWidth}px`;
      this.label.style.top = `${top - LABEL_GAP}px`;
    }

    if (cols !== this.cols) {
      this.cols = cols;
      this.seed();
    }
  },

  // Suite: a scatter of passed cells, FLAKY_COUNT flakes, and the
  // quarantine grid's bottom rows already occupied.
  seed() {
    const cols = this.cols;
    this.cells = new Array(cols * ROWS).fill(0).map(() => (Math.random() < PASS_RATIO ? "pass" : "empty"));
    this.flaky = [];
    const count = Math.min(FLAKY_COUNT, Math.floor((cols * ROWS) / 8));
    while (this.flaky.length < count) {
      const i = Math.floor(Math.random() * this.cells.length);
      if (this.cells[i] !== "flaky") {
        this.cells[i] = "flaky";
        this.flaky.push(i);
      }
    }
    // Sweep order: left to right, so the crosshair travels naturally.
    this.flaky.sort((a, b) => (a % cols) - (b % cols) || Math.floor(a / cols) - Math.floor(b / cols));
    this.quarantined = PREQUARANTINED;
    this.shift = 0;
    this.spawnIn = SPAWN_MAX_MS;
    this.phase = "move";
    this.phaseTime = 0;
    const first = this.cellCenter(this.suite, this.flaky[0]);
    this.cross = { x: first.x, y: first.y, fromX: first.x, fromY: first.y };
    if (!this.reduceMotion) {
      // Start the crosshair off the grid's top-left so the first move
      // reads as a sweep in.
      this.cross.x = this.cross.fromX = this.suite.x - 20;
      this.cross.y = this.cross.fromY = this.suite.y - 20;
    }
  },

  // A new flake surfaces somewhere that isn't already flaky.
  spawnFlake() {
    for (let attempt = 0; attempt < 20; attempt++) {
      const i = Math.floor(Math.random() * this.cells.length);
      if (this.cells[i] !== "flaky") {
        this.cells[i] = "flaky";
        this.flaky.push(i);
        return;
      }
    }
  },

  cellCenter(grid, index) {
    const col = index % grid.cols;
    const row = Math.floor(index / grid.cols);
    return { x: grid.x + col * PITCH + CELL / 2, y: grid.y + row * PITCH + CELL / 2 };
  },

  // Quarantine slots fill from the bottom row up, left to right.
  quarantineIndex(n) {
    const row = ROWS - 1 - Math.floor(n / QUARANTINE_COLS);
    const col = n % QUARANTINE_COLS;
    return row * QUARANTINE_COLS + col;
  },

  start() {
    if (this.frame || this.reduceMotion) return;
    this.lastTime = null;
    const tick = (time) => {
      this.frame = requestAnimationFrame(tick);
      const dt = this.lastTime ? Math.min(time - this.lastTime, 100) : 0;
      this.lastTime = time;
      this.update(dt);
      this.draw();
    };
    this.frame = requestAnimationFrame(tick);
  },

  stop() {
    if (this.frame) {
      cancelAnimationFrame(this.frame);
      this.frame = null;
    }
  },

  update(dt) {
    this.phaseTime += dt;

    this.spawnIn -= dt;
    if (this.spawnIn <= 0) {
      if (this.flaky.length < MAX_PENDING) this.spawnFlake();
      this.spawnIn = SPAWN_MIN_MS + Math.random() * (SPAWN_MAX_MS - SPAWN_MIN_MS);
    }

    // The crosshair always works on the oldest pending flake.
    const target = this.flaky[0];

    switch (this.phase) {
      case "move": {
        const dest = this.cellCenter(this.suite, target);
        const t = easeInOut(Math.min(1, this.phaseTime / MOVE_MS));
        this.cross.x = this.cross.fromX + (dest.x - this.cross.fromX) * t;
        this.cross.y = this.cross.fromY + (dest.y - this.cross.fromY) * t;
        if (this.phaseTime >= MOVE_MS) this.enter("hold");
        break;
      }
      case "hold":
        if (this.phaseTime >= HOLD_MS) {
          // Lift the flake out of the suite; it travels as a free cell.
          this.cells[target] = "empty";
          this.flight = {
            from: this.cellCenter(this.suite, target),
            to: this.cellCenter(this.quarantine, this.quarantineIndex(this.quarantined)),
          };
          this.enter("fly");
        }
        break;
      case "fly":
        if (this.phaseTime >= FLY_MS) {
          this.flight = null;
          this.quarantined += 1;
          this.flaky.shift();
          // A sixth row just started: slide the stack down one row and
          // let the oldest row fall off the bottom.
          if (this.quarantined > MAX_QUARANTINE_ROWS * QUARANTINE_COLS) {
            this.enter("shift");
          } else {
            this.enter("between");
          }
        }
        break;
      case "shift":
        this.shift = easeInOut(Math.min(1, this.phaseTime / SHIFT_MS));
        if (this.phaseTime >= SHIFT_MS) {
          this.shift = 0;
          this.quarantined -= QUARANTINE_COLS;
          this.enter("between");
        }
        break;
      case "between":
        if (this.phaseTime >= BETWEEN_MS) this.enter(this.flaky.length ? "move" : "idle");
        break;
      case "idle":
        // Nothing pending: the crosshair rests where it is until a new
        // flake surfaces.
        if (this.flaky.length) this.enter("move");
        break;
    }
  },

  enter(phase) {
    if (phase === "move") {
      this.cross.fromX = this.cross.x;
      this.cross.fromY = this.cross.y;
    }
    this.phase = phase;
    this.phaseTime = 0;
  },

  cell(x, y, stroke, fill) {
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.roundRect(x + 0.5, y + 0.5, CELL - 1, CELL - 1, RADIUS);
    if (fill) {
      ctx.fillStyle = fill;
      ctx.fill();
    }
    ctx.strokeStyle = stroke;
    ctx.stroke();
  },

  // A flake: the cell outlined and washed in yellow, with a solid yellow
  // core inset inside it.
  flake(x, y) {
    const c = this.colors;
    this.cell(x, y, c["flaky-stroke"], c["flaky-fill"]);
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.roundRect(x + CORE_INSET, y + CORE_INSET, CELL - 2 * CORE_INSET, CELL - 2 * CORE_INSET, 1);
    ctx.fillStyle = c["flaky-core"];
    ctx.fill();
  },

  drawCell(grid, index, state) {
    const col = index % grid.cols;
    const row = Math.floor(index / grid.cols);
    const x = grid.x + col * PITCH;
    const y = grid.y + row * PITCH;
    const c = this.colors;
    if (state === "pass") this.cell(x, y, c["pass-stroke"], c["pass-fill"]);
    else if (state === "flaky") this.flake(x, y);
    else if (state === "quarantined") this.cell(x, y, c["quarantine-stroke"], c["quarantine-fill"]);
    else this.cell(x, y, c.empty, null);
  },

  draw() {
    const ctx = this.ctx;
    const { width, height } = this;
    if (!width || !height || !this.suite) return;
    const c = this.colors;
    ctx.clearRect(0, 0, width, height);
    ctx.lineWidth = 1;

    for (let i = 0; i < this.cells.length; i++) this.drawCell(this.suite, i, this.cells[i]);

    for (let i = 0; i < QUARANTINE_COLS * ROWS; i++) this.drawCell(this.quarantine, i, "empty");

    // Quarantined stack, bottom row first. While shifting, every cell
    // slides down by `shift` rows and the bottom row fades as it leaves.
    const q = this.quarantine;
    const dy = this.shift * PITCH;
    for (let n = 0; n < this.quarantined; n++) {
      const col = n % QUARANTINE_COLS;
      const row = ROWS - 1 - Math.floor(n / QUARANTINE_COLS);
      const leaving = n < QUARANTINE_COLS && this.shift > 0;
      if (leaving) ctx.globalAlpha = 1 - this.shift;
      this.cell(q.x + col * PITCH, q.y + row * PITCH + dy, c["quarantine-stroke"], c["quarantine-fill"]);
      if (leaving) ctx.globalAlpha = 1;
    }

    // Crosshair: one hairline across the suite's rows and one down its
    // columns, meeting on the targeted flake, with a ring around it. It
    // stays on screen between targets.
    {
      const { x, y } = this.cross;
      const s = this.suite;
      // Cell centres sit on half pixels (x + 7.5), so snap with floor so
      // the ring and hairlines stay centred on the cell.
      const cx = Math.floor(x) + 0.5;
      const cy = Math.floor(y) + 0.5;
      const ring = CELL / 2 + 4; // half the ring's outer size
      ctx.strokeStyle = c.crosshair;
      // The hairlines stop at the ring so its inside stays clear.
      ctx.beginPath();
      ctx.moveTo(s.x - 20, cy);
      ctx.lineTo(cx - ring, cy);
      ctx.moveTo(cx + ring, cy);
      ctx.lineTo(s.x + s.width + 20, cy);
      ctx.moveTo(cx, s.y - 20);
      ctx.lineTo(cx, cy - ring);
      ctx.moveTo(cx, cy + ring);
      ctx.lineTo(cx, s.y + s.height + 20);
      ctx.stroke();
      ctx.beginPath();
      ctx.roundRect(cx - ring, cy - ring, ring * 2, ring * 2, RADIUS + 2);
      ctx.stroke();
    }

    if (this.flight) {
      const t = easeInOut(Math.min(1, this.phaseTime / FLY_MS));
      const x = this.flight.from.x + (this.flight.to.x - this.flight.from.x) * t;
      const y = this.flight.from.y + (this.flight.to.y - this.flight.from.y) * t;
      this.flake(x - CELL / 2, y - CELL / 2);
    }
  },
};

export { FlakyQuarantine };
