/*
 * Compute illustration — the task feed. A continuously scrolling list of job
 * steps: new rows rise from the bottom in a "processing" state (spinner) while
 * they're inside the bottom fade gradient, and flip to "complete" (green check)
 * once they scroll up out of it. Rows recycle off the top and are reassigned
 * the next task, so the feed runs forever.
 *
 * The hook builds/positions the rows on a <ul>; the task pool (labels +
 * durations, already localized) is passed as JSON.
 *
 * Options (data attributes on [data-part="tasks"]):
 *   data-tasks:    JSON array of { l: label, d: duration }
 *   data-row-h:    row height in px
 *   data-panel-h:  panel content height in px
 */

const ICON_DONE = `<svg data-part="icon-done" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 12m-9 0a9 9 0 1 0 18 0a9 9 0 1 0 -18 0"/><path d="M9 12l2 2l4 -4"/></svg>`;
const ICON_PROCESSING = `<svg data-part="icon-processing" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9" stroke-dasharray="0.1 3.9"/></svg>`;

const pad2 = (n) => String(n).padStart(2, "0");
// Compact in the row ("2s" / "1m 08s"), padded in the stat ("00m 12s"), the
// same format as the cache stats so the centered value never reflows.
const fmtCompact = (s) => (s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${pad2(s % 60)}s`);
const fmtPadded = (s) => `${pad2(Math.floor(s / 60))}m ${pad2(s % 60)}s`;

export const TaskFeed = {
  mounted() {
    this.el = this.el;
    this.list = this.el.querySelector('[data-part="task-list"]');
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    try {
      this.tasks = JSON.parse(this.el.dataset.tasks || "[]");
    } catch {
      this.tasks = [];
    }
    if (!this.tasks.length) this.tasks = [{ l: "Run actions", d: "10s" }];

    this.rowH = Number(this.el.dataset.rowH) || 32;
    this.panelH = Number(this.el.dataset.panelH) || this.list.clientHeight || 256;
    this.speed = 0.03; // px/ms (~one row per second)
    // Rows are "processing" while below this line (inside the bottom fade).
    this.completeAbove = this.panelH * 0.72;

    const illustration = this.el.closest('[data-part="illustration"]');
    this.durStat = illustration && illustration.querySelector('[data-stat="duration"]');

    this.N = Math.ceil(this.panelH / this.rowH) + 2;
    this.recent = []; // recently-shown tasks, to avoid near-repeats
    this.rows = [];
    this.list.replaceChildren();
    for (let i = 0; i < this.N; i++) {
      const row = this.buildRow();
      row.y = i * this.rowH;
      this.assign(row);
      this.list.appendChild(row.el);
      this.rows.push(row);
    }
    this.layout();

    if (this.reduced) return;

    this.last = null;
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      if (this.el.checkVisibility && !this.el.checkVisibility()) {
        this.last = null;
        return;
      }
      const dt = this.last == null ? 16 : now - this.last;
      this.last = now;
      const total = this.N * this.rowH;
      for (const row of this.rows) {
        row.y -= this.speed * dt;
        if (row.y <= -this.rowH) {
          row.y += total;
          this.assign(row); // recycled → new task, back to processing
        }
      }
      this.layout();
    };
    this.raf = requestAnimationFrame(tick);
  },

  destroyed() {
    if (this.raf) cancelAnimationFrame(this.raf);
  },

  buildRow() {
    const el = document.createElement("li");
    el.setAttribute("data-part", "task-row");
    el.innerHTML =
      `<span data-part="task-icon">${ICON_DONE}${ICON_PROCESSING}</span>` +
      `<span data-part="task-label"></span>` +
      `<span data-part="task-dur"></span>` +
      `<span data-part="task-dots"><i></i><i></i><i></i></span>`;
    return {
      el,
      label: el.querySelector('[data-part="task-label"]'),
      dur: el.querySelector('[data-part="task-dur"]'),
      y: 0,
    };
  },

  // Pick a random task, avoiding the few most recently shown so nothing
  // repeats within the visible window.
  assign(row) {
    const pool = this.tasks;
    const avoid = Math.min(4, pool.length - 1);
    let t;
    let tries = 0;
    do {
      t = pool[Math.floor(Math.random() * pool.length)];
    } while (this.recent.includes(t) && ++tries < 20);
    this.recent.push(t);
    if (this.recent.length > avoid) this.recent.shift();
    row.secs = t.s || 0;
    row.label.textContent = t.l;
    row.dur.textContent = fmtCompact(row.secs);
  },

  layout() {
    for (const row of this.rows) {
      row.el.style.transform = `translateY(${row.y}px)`;
      const state = row.y + this.rowH / 2 > this.completeAbove ? "processing" : "complete";
      const prev = row.el.getAttribute("data-state");
      if (prev !== state) {
        row.el.setAttribute("data-state", state);
        // When a step finishes, surface its duration in the stats bar — padded
        // "XXm YYs" like the cache stats so the value stays a constant width.
        if (state === "complete" && prev === "processing" && this.durStat) {
          this.durStat.textContent = fmtPadded(row.secs || 0);
        }
      }
    }
  },
};
