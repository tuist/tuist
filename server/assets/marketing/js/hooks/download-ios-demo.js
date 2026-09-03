/*
 * Download page iOS demo: opening a preview in the Tuist iOS app and running
 * it on the device. There is no cursor — it's a phone — so taps show as the
 * tapped control tinting. One looped round:
 *   1. rest    — the Previews list shows; the first stanza line is lit.
 *   2. tap     — the Tuist row tints; the preview's detail page slides in
 *                from the right and the second line ("inspect them in
 *                detail") lights up.
 *   3. run     — "Run" tints; the app closes like iOS closes apps (the
 *                live window shrinks into a squircle on the Tuist tile's
 *                spot, its icon fading over it, while the home screen
 *                un-zooms and un-blurs behind it). The tile is slipped in
 *                underneath, so the window's icon becomes the tile, which
 *                then installs behind
 *                the progress pie (the macOS demo's install). The third
 *                line ("runs them directly on your device") lights up.
 *   4. open    — the installed app opens like iOS opens apps (the squircle
 *                grows from its tile into the screen), back on the Previews
 *                list with the first line
 *                lit; the tile is cleared underneath so the next round
 *                installs afresh, and the round holds.
 *
 * Page push/pop, taps, the app close/open and the stanza highlight are CSS
 * transitions keyed off attributes; the progress pie runs through the Web
 * Animations API so leaving the viewport freezes it with the timers and
 * resumes in place. Under reduced motion nothing runs and the list shows
 * as rendered — except the status bar clocks, which always show the
 * visitor's current time, iOS style ("9:41": hour and minute, no period),
 * refreshed on each minute boundary like the macOS menu bar.
 */

const REST_MS = 2200;
const TAP_MS = 180;
const PUSH_MS = 520;
const DETAIL_HOLD_MS = 3200;
const TILE_SHOW_MS = 320; // into the close: the tile is placed under the shrinking window
const INSTALL_START_MS = 560; // after that: the window has faded and the tile is the logo
const INSTALL_MS = 4200;
const INSTALL_SETTLE_MS = 700;
const OPEN_MS = 560;
const LIST_HOLD_MS = 1200;

const INSTALLING_LABEL = "Installing…";
const APP_NAME = "Tuist";

export const DownloadIosDemo = {
  mounted() {
    this.scene = this.el;
    this.screen = this.el.querySelector('[data-part="screen"]');
    this.shell = this.el.querySelector('[data-part="app-shell"]');
    this.home = this.el.querySelector('[data-part="home-screen"]');
    this.pages = this.el.querySelector('[data-part="pages"]');
    this.row = this.el.querySelector('[data-part="preview"][data-preview="tuist"]');
    this.run = this.el.querySelector('[data-part="preview-run"][data-action="run"]');
    this.back = this.el.querySelector('[data-part="nav-button"][data-action="back"]');
    this.tile = this.el.querySelector('[data-part="app"][data-installable]');
    this.tileLabel = this.tile && this.tile.querySelector('[data-part="app-label"]');
    this.pie = this.tile && this.tile.querySelector('[data-part="app-progress-pie"]');
    const section = this.el.closest('[data-section="ios"]');
    this.lines = section ? Array.from(section.querySelectorAll('[data-part="line"]')) : [];
    this.startClock();
    if (!this.screen || !this.shell || !this.home || !this.pages || !this.row || !this.run || !this.back) return;
    if (!this.tile || !this.tileLabel || !this.pie) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    this.visible = false;
    this.pending = null;
    this.animations = new Set();

    this.scene.setAttribute("data-animated", "");
    this.setStep(0);

    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.visible = entry.isIntersecting;
        this.sync();
      },
      { threshold: 0.25 },
    );
    this.observer.observe(this.scene);

    this.wait(REST_MS, () => this.round());
  },

  destroyed() {
    if (this.observer) this.observer.disconnect();
    if (this.pending && this.pending.id) window.clearTimeout(this.pending.id);
    if (this.clock) window.clearTimeout(this.clock);
    for (const animation of this.animations) animation.cancel();
  },

  round() {
    this.tap(this.row, () => {
      this.pages.setAttribute("data-screen", "detail");
      this.setStep(1);
      this.wait(PUSH_MS + DETAIL_HOLD_MS, () => {
        this.tap(this.run, () => {
          this.closeApp();
          this.setStep(2);
          this.wait(TILE_SHOW_MS, () => {
            this.setTile("installing", true);
            this.wait(INSTALL_START_MS, () => {
              this.sweepPie(() => {
                this.setTile("installed");
                this.wait(INSTALL_SETTLE_MS, () => {
                  this.resetPages();
                  this.openApp();
                  this.setStep(0);
                  this.wait(OPEN_MS, () => {
                    this.setTile(null);
                    this.wait(LIST_HOLD_MS + REST_MS, () => this.round());
                  });
                });
              });
            });
          });
        });
      });
    });
  },

  // A touch: the control tints for a beat, then the action runs.
  tap(el, done) {
    el.setAttribute("data-pressed", "");
    this.wait(TAP_MS, () => {
      el.removeAttribute("data-pressed");
      done();
    });
  },

  // iOS shrinks a closing app into its icon: hand the CSS the tile's spot
  // and size in the shell's own coordinates (the unzoomed home screen
  // fills the shell exactly, so its layout scales by one factor).
  closeApp() {
    // Layout offsets ignore the home screen's zoom and the tile's own
    // pop-in scale (it is still hidden at 60% when the app closes), so
    // the window lands on the tile at its full size.
    const icon = this.tile.querySelector("img");
    // The shell wraps the screen's 1px bleed ring; the unzoomed home
    // screen fills the area inside it.
    const ring = 1;
    const homeScale = (this.shell.offsetWidth - 2 * ring) / this.home.offsetWidth;
    const x = ring + (this.tile.offsetLeft + icon.offsetLeft) * homeScale;
    const y = ring + (this.tile.offsetTop + icon.offsetTop) * homeScale;
    const scale = (icon.offsetWidth * homeScale) / this.shell.offsetWidth;
    this.shell.style.setProperty("--open-x", `${x}px`);
    this.shell.style.setProperty("--open-y", `${y}px`);
    this.shell.style.setProperty("--open-scale", `${scale}`);
    this.screen.setAttribute("data-app", "closed");
  },

  openApp() {
    this.screen.removeAttribute("data-app");
  },

  // Back to the Previews list without the slide, while the app is closed
  // and nobody can see it.
  resetPages() {
    this.pages.setAttribute("data-instant", "");
    this.pages.removeAttribute("data-screen");
    void this.pages.offsetWidth;
    this.pages.removeAttribute("data-instant");
  },

  // The home screen tile: absent between rounds, "installing" behind the
  // progress pie, "installed" once it clears. The pie is wound back to
  // empty whenever the tile leaves so the next install starts from zero.
  // `instant` skips the pop-in: the tile is placed while the closing app
  // window still covers it, so the window's icon simply becomes the tile.
  setTile(state, instant = false) {
    if (instant) this.tile.setAttribute("data-instant", "");
    if (state) {
      this.tile.setAttribute("data-install", state);
    } else {
      this.tile.removeAttribute("data-install");
      this.pie.style.strokeDashoffset = "100";
    }
    this.tileLabel.textContent = state === "installing" ? INSTALLING_LABEL : APP_NAME;
    if (instant) {
      void this.tile.offsetWidth;
      this.tile.removeAttribute("data-instant");
    }
  },

  // iOS's install pie: the wedge sweeps clockwise from empty to full,
  // easing in like a real download that starts slow.
  sweepPie(done) {
    this.animate(
      this.pie,
      [{ strokeDashoffset: 100 }, { strokeDashoffset: 0 }],
      { duration: INSTALL_MS, easing: "cubic-bezier(0.4, 0, 0.6, 1)", fill: "forwards" },
      done,
    );
  },

  // Light the stanza line for the current step; the others fall back to
  // tertiary via CSS.
  setStep(index) {
    this.lines.forEach((line, i) => line.toggleAttribute("data-active", i === index));
  },

  startClock() {
    const timeEls = Array.from(this.el.querySelectorAll('[data-part="status-time"]'));
    if (timeEls.length === 0) return;
    const format = new Intl.DateTimeFormat(document.documentElement.lang || undefined, {
      hour: "numeric",
      minute: "2-digit",
    });
    const tick = () => {
      const now = new Date();
      // Drop the day period and whatever separates it ("9:41 AM" → "9:41").
      const text = format
        .formatToParts(now)
        .filter((part) => part.type !== "dayPeriod")
        .map((part) => part.value)
        .join("")
        .trim();
      for (const el of timeEls) el.textContent = text;
      const untilNextMinute = 60000 - (now.getSeconds() * 1000 + now.getMilliseconds());
      this.clock = window.setTimeout(tick, untilNextMinute + 50);
    };
    tick();
  },

  animate(el, keyframes, options, done) {
    const animation = el.animate(keyframes, options);
    this.animations.add(animation);
    if (!this.visible) animation.pause();
    animation.onfinish = () => {
      this.animations.delete(animation);
      // commitStyles throws for an element that isn't rendered; the demo
      // carries on without it.
      try {
        animation.commitStyles();
      } catch (_error) {}
      animation.cancel();
      if (done) done();
    };
    animation.oncancel = () => this.animations.delete(animation);
  },

  // One pending timer at a time; leaving the viewport banks the time left
  // so the step resumes where it stopped rather than restarting.
  wait(ms, fn) {
    this.pending = { fn, remaining: ms, id: null, startedAt: 0 };
    this.sync();
  },

  sync() {
    const running = this.visible;
    const pending = this.pending;
    if (pending) {
      if (running && !pending.id) {
        pending.startedAt = performance.now();
        pending.id = window.setTimeout(() => {
          this.pending = null;
          pending.fn();
        }, pending.remaining);
      } else if (!running && pending.id) {
        window.clearTimeout(pending.id);
        pending.remaining = Math.max(0, pending.remaining - (performance.now() - pending.startedAt));
        pending.id = null;
      }
    }
    for (const animation of this.animations) {
      if (running) animation.play();
      else animation.pause();
    }
    this.scene.toggleAttribute("data-paused", !running);
  },
};
