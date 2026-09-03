/*
 * Download page macOS demo: the menu bar app's popover installs previews
 * onto the simulator, alternating Tuist and Wikipedia. One round:
 *   1. rest      — status reads "Ready", the cursor idles below the popover;
 *                  the simulator and phone are not there yet.
 *   2. approach  — the cursor glides onto this round's app tile.
 *   3. hover     — the tile darkens; a beat later it presses.
 *   4. install   — status rolls to "Installing preview" beside a spinner and
 *                  the simulator bar and phone rise in together.
 *   5. phone     — the app's tile pops onto the home screen labelled
 *                  "Installing…" and iOS's progress pie sweeps round it.
 *   6. done      — the tile clears and reads its name; status rolls to
 *                  "Installed <App>@<hash>"; the cursor drifts back to rest
 *                  and the round holds.
 *   7. reset     — status rolls back to "Ready", the device fades away, the
 *                  tile comes off the home screen and the next round starts
 *                  on the other app. Only the app being installed is ever on
 *                  the phone: the other's tile is taken out of the grid for
 *                  the round so this one lands in the first free slot.
 *
 * Status changes fade the text up and roll the new one in from below. The
 * cursor, the text roll and the progress pie run through the Web Animations
 * API so leaving the viewport can freeze them mid-flight together with the
 * timers and resume where they stopped; the popover spinner is a CSS
 * animation paused via data-paused on the scene, and the device / tile
 * reveals are short CSS transitions keyed off attributes. Under reduced
 * motion nothing runs and the server-rendered "installed" comp shows
 * instead.
 */

const REST_MS = 1400;
const MOVE_MS = 900;
const HOVER_MS = 420;
const PRESS_MS = 140;
const DEVICE_IN_MS = 760;
const TILE_IN_MS = 360;
const INSTALL_MS = 4200;
const INSTALL_SETTLE_MS = 380;
const DONE_BEAT_MS = 600;
const LEAVE_MS = 700;
const INSTALLED_MS = 4000;
const DEVICE_OUT_MS = 700;
const ROLL_OUT_MS = 160;
const ROLL_IN_MS = 240;
const ROLL_SHIFT = 6;
const EASE = "cubic-bezier(0.32, 0.72, 0, 1)";

const STATUS = {
  ready: "Ready",
  installing: "Installing preview",
};

const INSTALLING_LABEL = "Installing…";

// The apps the rounds cycle through, matched by data-app to a tile in the
// popover tray and one on the phone's home screen.
const APPS = [
  { key: "tuist", name: "Tuist", hash: "22d00c0" },
  { key: "wikipedia", name: "Wikipedia", hash: "8b1e4f2" },
];

export const DownloadMacDemo = {
  mounted() {
    this.scene = this.el;
    this.status = this.el.querySelector('[data-part="popover-status"]');
    this.statusText = this.el.querySelector('[data-part="popover-status-text"]');
    this.cursor = this.el.querySelector('[data-part="cursor"]');
    if (!this.status || !this.statusText || !this.cursor) return;

    this.apps = APPS.map((app) => {
      const tray = this.el.querySelector(`[data-part="popover-app"][data-app="${app.key}"]`);
      const tile = this.el.querySelector(`[data-part="app"][data-app="${app.key}"]`);
      return {
        ...app,
        tray,
        tile,
        label: tile && tile.querySelector('[data-part="app-label"]'),
        pie: tile && tile.querySelector('[data-part="app-progress-pie"]'),
      };
    });
    if (this.apps.some((app) => !app.tray || !app.tile || !app.label || !app.pie)) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    this.visible = false;
    this.pending = null;
    this.animations = new Set();
    this.turn = 0;

    this.scene.setAttribute("data-animated", "");
    this.setStage("ready", false);
    this.placeCursor(this.restPoint());

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
    for (const animation of this.animations) animation.cancel();
  },

  round() {
    const app = this.apps[this.turn % this.apps.length];
    this.turn += 1;
    for (const other of this.apps) other.tile.toggleAttribute("hidden", other !== app);
    this.moveCursor(this.iconPoint(app), MOVE_MS, () => {
      app.tray.setAttribute("data-hover", "");
      this.wait(HOVER_MS, () => {
        app.tray.setAttribute("data-pressed", "");
        this.wait(PRESS_MS, () => {
          app.tray.removeAttribute("data-pressed");
          this.setStage("installing");
          this.scene.setAttribute("data-device", "");
          this.wait(DEVICE_IN_MS, () => {
            this.setTile(app, "installing");
            this.wait(TILE_IN_MS, () => {
              this.sweepPie(app, () => {
                this.setTile(app, "installed");
                this.wait(INSTALL_SETTLE_MS, () => {
                  this.setStage("installed", true, app);
                  this.wait(DONE_BEAT_MS, () => {
                    app.tray.removeAttribute("data-hover");
                    this.moveCursor(this.restPoint(), LEAVE_MS);
                    this.wait(INSTALLED_MS, () => {
                      this.setStage("ready");
                      this.scene.removeAttribute("data-device");
                      this.wait(DEVICE_OUT_MS, () => {
                        this.setTile(app, null);
                        this.wait(REST_MS, () => this.round());
                      });
                    });
                  });
                });
              });
            });
          });
        });
      });
    });
  },

  statusFor(stage, app) {
    return stage === "installed" ? `Installed ${app.name}@${app.hash}` : STATUS[stage];
  },

  // Swap the status line, rolling the old text up and out and the new one
  // in from below. The stage attribute flips at the swap so the spinner
  // appears together with its text.
  setStage(stage, roll = true, app = null) {
    if (!roll) {
      this.statusText.textContent = this.statusFor(stage, app);
      this.status.setAttribute("data-stage", stage);
      return;
    }
    this.animate(
      this.statusText,
      [
        { opacity: 1, transform: "translateY(0)" },
        { opacity: 0, transform: `translateY(-${ROLL_SHIFT}px)` },
      ],
      { duration: ROLL_OUT_MS, easing: "ease-in", fill: "forwards" },
      () => {
        this.statusText.textContent = this.statusFor(stage, app);
        this.status.setAttribute("data-stage", stage);
        this.animate(
          this.statusText,
          [
            { opacity: 0, transform: `translateY(${ROLL_SHIFT}px)` },
            { opacity: 1, transform: "translateY(0)" },
          ],
          { duration: ROLL_IN_MS, easing: EASE, fill: "forwards" },
        );
      },
    );
  },

  // The app's home screen tile: absent between rounds, "installing" behind
  // the progress pie, "installed" once it clears. The pie is wound back to
  // empty whenever the tile leaves so the next install starts from zero.
  setTile(app, state) {
    if (state) {
      app.tile.setAttribute("data-install", state);
    } else {
      app.tile.removeAttribute("data-install");
      app.pie.style.strokeDashoffset = "100";
    }
    app.label.textContent = state === "installing" ? INSTALLING_LABEL : app.name;
  },

  // iOS's install pie: the wedge sweeps clockwise from empty to full,
  // easing in like a real download that starts slow.
  sweepPie(app, done) {
    this.animate(
      app.pie,
      [{ strokeDashoffset: 100 }, { strokeDashoffset: 0 }],
      { duration: INSTALL_MS, easing: "cubic-bezier(0.4, 0, 0.6, 1)", fill: "forwards" },
      done,
    );
  },

  // Cursor targets, in scene coordinates: the tip lands on the app's tray
  // tile centre; rest is below the popover, a little right of its middle.
  iconPoint(app) {
    const scene = this.scene.getBoundingClientRect();
    const icon = app.tray.querySelector("img").getBoundingClientRect();
    return { x: icon.left - scene.left + icon.width / 2, y: icon.top - scene.top + icon.height / 2 };
  },

  restPoint() {
    const scene = this.scene.getBoundingClientRect();
    const popover = this.status.closest('[data-part="popover"]').getBoundingClientRect();
    return { x: popover.left - scene.left + popover.width * 0.55, y: popover.bottom - scene.top + 110 };
  },

  placeCursor(point) {
    this.cursor.style.transform = `translate(${point.x}px, ${point.y}px)`;
  },

  moveCursor(point, duration, done) {
    this.animate(
      this.cursor,
      [{ transform: this.cursor.style.transform }, { transform: `translate(${point.x}px, ${point.y}px)` }],
      { duration, easing: EASE, fill: "forwards" },
      () => {
        this.placeCursor(point);
        if (done) done();
      },
    );
  },

  animate(el, keyframes, options, done) {
    const animation = el.animate(keyframes, options);
    this.animations.add(animation);
    if (!this.running()) animation.pause();
    animation.onfinish = () => {
      this.animations.delete(animation);
      // commitStyles throws for an element that isn't rendered (the phone
      // is display: none on mobile); the demo carries on without it.
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

  running() {
    return this.visible;
  },

  sync() {
    const running = this.running();
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
