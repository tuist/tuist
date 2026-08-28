/*
 * "Built into your build platform" scene animation, looped. No traveling
 * pulses — the dashed wires' CSS drift and the runner dot's resting pulse
 * carry the motion; this hook paces the narrative beats:
 *
 *   1. commit — a beat after the new commit lands in the box.
 *   2. build  — the job "executes": the CI line reads `in progress` in
 *               pending grey with a living ellipsis.
 *   3. lands  — the targets count rolls, the ellipsis rolls into the real
 *               duration, and the line turns passed-green.
 *   4. report — the hit/miss counters grow (cumulative, so the ratio card
 *               is their real quotient) and cpu/mem re-sample.
 *   5. idle   — the commit box and CI job rewrite typewriter-style to the
 *               next entry, then repeat.
 *
 * All typewriters run off one rAF clock (per-element intervals jittered).
 * Reduced motion: no loop at all — the static first frame.
 */

const COMMITS = [
  { sha: "a3f92e1", msg: "feat: offline sync" },
  { sha: "4be9f07", msg: "fix: deep links" },
  { sha: "c218ad3", msg: "perf: faster boot" },
  { sha: "91f4e2b", msg: "feat: watch app" },
  { sha: "e7d05c9", msg: "chore: bump deps" },
];

const COMMIT_MS = 800;
const BUILD_MS = 2600;
const REPORT_MS = 2000;
const SYNC_MS = 1600;
const IDLE_MS = 2000;

export const ComputeBuildPlatform = {
  mounted() {
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const commitBox = this.el.querySelector('[data-box="commit"]');
    const jobBox = this.el.querySelector('[data-box="ci-job"]');
    this.commitBox = commitBox;
    this.jobBox = jobBox;
    this.commitTitle = commitBox && commitBox.querySelector('[data-part="title"]');
    this.commitSubtitle = commitBox && commitBox.querySelector('[data-part="subtitle"]');
    this.jobTitle = jobBox && jobBox.querySelector('[data-part="title"]');
    this.jobSubtitle = jobBox && jobBox.querySelector('[data-part="subtitle"]');
    this.commitIndex = 0;
    this.jobNumber = 1042;

    // Rolling numbers elsewhere in the scene: the targets count, the
    // hit/miss badge counters (cumulative, so the ratio is real math),
    // and the stat cards' values.
    const badgeLabel = (chip) => this.el.querySelector(`[data-chip="${chip}"] .noora-badge > span:last-child`);
    this.targetsTitle = this.el.querySelector('[data-box="targets"] [data-part="title"]');
    this.activitySubtitle = this.el.querySelector('[data-box="cache-activity"] [data-part="subtitle"]');
    this.metricsSubtitle = this.el.querySelector('[data-box="machine-metrics"] [data-part="subtitle"]');
    this.hitLabel = badgeLabel("hit");
    this.missLabel = badgeLabel("miss");
    this.stats = { hits: 134, misses: 8 };
    this.targets = 24;

    if (this.reduced) return;

    this.phase = "commit";
    this.phaseStart = null;
    this.swapTimers = [];
    this.typers = [];

    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      // Off-screen: hold the cycle where it is, resume when visible.
      if (this.el.checkVisibility && !this.el.checkVisibility()) {
        this.phaseStart = null;
        return;
      }
      if (this.phaseStart == null) {
        this.phaseStart = now;
        this.phase = "commit";
      }
      this.updateTypers(now);
      this.advance(now);
    };
    this.raf = requestAnimationFrame(tick);
  },

  destroyed() {
    if (this.raf) cancelAnimationFrame(this.raf);
    if (this.swapTimers) this.swapTimers.forEach((id) => window.clearTimeout(id));
  },

  next(phase, now) {
    this.phase = phase;
    this.phaseStart = now;
  },

  advance(now) {
    const t = now - this.phaseStart;

    if (this.phase === "commit") {
      if (t >= COMMIT_MS) this.next("build", now);
      return;
    }

    if (this.phase === "build") {
      if (t >= BUILD_MS) {
        this.rollTargets();
        this.resolveJobTime();
        this.next("report", now);
      }
      return;
    }

    if (this.phase === "report") {
      if (t >= REPORT_MS) {
        this.rollResults();
        this.next("sync", now);
      }
      return;
    }

    if (this.phase === "sync") {
      if (t >= SYNC_MS) {
        this.swapEntries();
        this.next("idle", now);
      }
      return;
    }

    if (t >= IDLE_MS) this.next("commit", now);
  },

  // Slot-roll a text element: digits churn randomly for a beat, then
  // settle on the final string (tabular digits keep the line steady —
  // the cache page's counter trick).
  rollText(el, finalText) {
    if (!el) {
      return;
    }
    const start = performance.now();
    const timer = window.setInterval(() => {
      if (performance.now() - start >= 520) {
        el.textContent = finalText;
        window.clearInterval(timer);
        return;
      }
      el.textContent = finalText.replace(/[0-9]/g, () => Math.floor(Math.random() * 10));
    }, 60);
    // Interval and timeout ids share a namespace, so the destroyed()
    // sweep clears these too.
    this.swapTimers.push(timer);
  },

  // A build finished compiling: draw this job's target count.
  rollTargets() {
    this.targets = 16 + Math.floor(Math.random() * 25);
    this.rollText(this.targetsTitle, `${this.targets} targets`);
  },

  // ...and the job lands: the pending grey line turns passed-green and
  // the dots roll into the real duration.
  resolveJobTime() {
    if (this.dotsTimer) window.clearInterval(this.dotsTimer);
    if (this.jobBox) this.jobBox.removeAttribute("data-state");
    const minutes = 2 + Math.floor(Math.random() * 5);
    const seconds = Math.floor(Math.random() * 60);
    this.rollText(this.jobSubtitle, `passed · ${minutes}m ${seconds}s`);
  },

  // While the next job runs, the time is a living ellipsis. The dots pad
  // to a constant three columns (nbsp in the mono face), so the centered
  // line keeps its width and the label never shuffles.
  startDots() {
    if (this.dotsTimer) window.clearInterval(this.dotsTimer);
    let n = 1;
    this.dotsTimer = window.setInterval(() => {
      n = (n % 3) + 1;
      if (this.jobSubtitle) {
        this.jobSubtitle.textContent = `in progress · ${"·".repeat(n).padEnd(3, " ")}`;
      }
    }, 450);
    this.swapTimers.push(this.dotsTimer);
  },

  // Results land on the cards: this job's targets split into cache hits
  // and misses, the cumulative counters grow, and the hit ratio is their
  // real quotient. cpu/mem just re-sample plausible load.
  rollResults() {
    const misses = Math.random() < 0.4 ? 1 + Math.floor(Math.random() * 4) : 0;
    this.stats.hits += this.targets - misses;
    this.stats.misses += misses;
    // Keep the badge widths sane on very long sessions.
    if (this.stats.hits > 960) this.stats = { hits: 134, misses: 8 };
    const ratio = Math.round((100 * this.stats.hits) / (this.stats.hits + this.stats.misses));
    const cpu = 45 + Math.floor(Math.random() * 45);
    const mem = 12 + Math.floor(Math.random() * 27);
    this.rollText(this.hitLabel, `hit · ${this.stats.hits}`);
    this.rollText(this.missLabel, `miss · ${this.stats.misses}`);
    this.rollText(this.activitySubtitle, `${ratio}% hit ratio`);
    this.rollText(this.metricsSubtitle, `cpu ${cpu}% · mem ${mem}/48`);
  },

  // Typewriter rewrite: erase the current text char by char, then type
  // the replacement — the hero diff's voice, scene-sized. Driven off the
  // main rAF clock (updateTypers) rather than per-element intervals,
  // whose timer jitter made the rewrites stutter.
  typeText(el, finalText, done) {
    if (!el) return;
    this.typers = this.typers.filter((ty) => ty.el !== el);
    this.typers.push({ el, from: el.textContent, to: finalText, start: null, done });
  },

  updateTypers(now) {
    if (!this.typers.length) return;
    const ERASE_MS = 24;
    const TYPE_MS = 55;
    this.typers = this.typers.filter((ty) => {
      if (ty.start == null) ty.start = now;
      const t = now - ty.start;
      const eraseDur = ty.from.length * ERASE_MS;
      if (t < eraseDur) {
        const left = ty.from.length - Math.floor(t / ERASE_MS);
        ty.el.textContent = ty.from.slice(0, Math.max(0, left));
        return true;
      }
      const typed = Math.floor((t - eraseDur) / TYPE_MS);
      if (typed >= ty.to.length) {
        ty.el.textContent = ty.to;
        if (ty.done) ty.done();
        return false;
      }
      ty.el.textContent = ty.to.slice(0, typed);
      return true;
    });
  },

  // The process completed: the commit box rewrites to its next entry and
  // the CI job takes its next number, typewriter-style.
  swapEntries() {
    this.commitIndex = (this.commitIndex + 1) % COMMITS.length;
    const commit = COMMITS[this.commitIndex];
    this.typeText(this.commitTitle, commit.sha);
    this.typeText(this.commitSubtitle, commit.msg);

    this.jobNumber += 1 + Math.floor(Math.random() * 3);
    // "CI job #" is constant — only the number animates (a digit roll),
    // no full rewrite.
    this.rollText(this.jobTitle, `CI job #${this.jobNumber}`);
    // The next job hasn't passed yet: pending grey until it lands.
    if (this.jobBox) this.jobBox.setAttribute("data-state", "running");
    this.typeText(this.jobSubtitle, "in progress · ·", () => this.startDots());
  },
};
