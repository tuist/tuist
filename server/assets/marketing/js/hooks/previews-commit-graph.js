/**
 * PreviewsCommitGraph: animates the previews hero's commit graph.
 *
 * Purple streaks travel along the invisible route paths ([data-part="route"],
 * each running from a commit to the phone's edge) using a stroke-dash window
 * that slides from the route's start to its end. When a streak reaches the
 * phone it pulses the entry point and advances the phone's screen state
 * (data-screen), which the CSS morphs between — the same shapes, nudged.
 *
 * Streaks launch on a random cadence and may overlap. The loop pauses while
 * the stage is off-screen or the tab is hidden, and never starts under
 * prefers-reduced-motion (the static graph is the whole story then).
 *
 * The stage is a fixed 1200x300 canvas of Figma coordinates; the hook also
 * measures the slot around it and sets --stage-scale so the CSS shrinks the
 * whole stage to fit narrower cards.
 */
const STAGE_WIDTH = 1200;
const SVG_NS = "http://www.w3.org/2000/svg";
const SPEED = 420; // px per second along the route
const HEAD = 26; // bright head length (px)
const TAIL = 84; // faint tail length (px)
const SCREENS = 3;
const LAUNCH_MIN_MS = 700;
const LAUNCH_MAX_MS = 1400;
const FADE_MS = 260;

function between(min, max) {
  return min + Math.random() * (max - min);
}

const PreviewsCommitGraph = {
  mounted() {
    this.slot = this.el.parentElement;
    this.fit();
    this.resizer = new ResizeObserver(() => this.fit());
    this.resizer.observe(this.slot);

    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.svg = this.el.querySelector('[data-part="connectors"]');
    this.phone = this.el.querySelector('[data-part="phone"]');
    this.routes = Array.from(this.el.querySelectorAll('[data-part="route"]')).map((path) => {
      const length = path.getTotalLength();
      const end = path.getPointAtLength(length);
      return { d: path.getAttribute("d"), length, end };
    });
    this.screen = 0;
    this.lastRoute = -1;
    this.visible = false;
    this.timer = null;
    this.inflight = new Set();
    if (this.reduced || this.routes.length === 0) return;

    this.onVisibility = () => this.sync();
    document.addEventListener("visibilitychange", this.onVisibility);
    this.observer = new IntersectionObserver(
      (entries) => {
        this.visible = entries.some((entry) => entry.isIntersecting);
        this.sync();
      },
      { threshold: 0.2 },
    );
    this.observer.observe(this.el);
  },

  destroyed() {
    if (this.resizer) this.resizer.disconnect();
    if (this.observer) this.observer.disconnect();
    if (this.onVisibility) document.removeEventListener("visibilitychange", this.onVisibility);
    this.stop();
  },

  fit() {
    const width = this.slot.clientWidth;
    if (!width) return;
    const scale = Math.min(1, width / STAGE_WIDTH);
    this.slot.style.setProperty("--stage-scale", scale.toFixed(4));
  },

  sync() {
    const active = this.visible && document.visibilityState === "visible";
    if (active && !this.timer) this.scheduleNext(between(200, 600));
    if (!active) this.stop();
  },

  stop() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    this.inflight.forEach((group) => group.remove());
    this.inflight.clear();
  },

  scheduleNext(delay) {
    this.timer = setTimeout(() => {
      this.timer = null;
      this.launch();
      this.scheduleNext(between(LAUNCH_MIN_MS, LAUNCH_MAX_MS));
    }, delay);
  },

  pickRoute() {
    let index = Math.floor(Math.random() * this.routes.length);
    if (index === this.lastRoute) index = (index + 1) % this.routes.length;
    this.lastRoute = index;
    return this.routes[index];
  },

  launch() {
    const route = this.pickRoute();
    const group = document.createElementNS(SVG_NS, "g");
    group.setAttribute("data-part", "streak");
    const duration = (route.length / SPEED) * 1000;
    const layers = [
      { window: TAIL, layer: "tail" },
      { window: HEAD, layer: "head" },
    ];

    layers.forEach(({ window, layer }) => {
      const path = document.createElementNS(SVG_NS, "path");
      path.setAttribute("d", route.d);
      path.setAttribute("data-layer", layer);
      path.setAttribute("stroke-dasharray", `${window} ${route.length + window}`);
      path.setAttribute("stroke-dashoffset", `${window}`);
      group.appendChild(path);
      // Offset `window` parks the dash just before the start; offset
      // `window - length` puts its head exactly on the route's end.
      path.animate([{ strokeDashoffset: window }, { strokeDashoffset: window - route.length }], {
        duration,
        easing: "linear",
        fill: "forwards",
      });
    });

    this.svg.appendChild(group);
    this.inflight.add(group);

    setTimeout(() => {
      if (!this.inflight.has(group)) return;
      this.hit(route);
      const fade = group.animate([{ opacity: 1 }, { opacity: 0 }], { duration: FADE_MS, fill: "forwards" });
      fade.onfinish = () => {
        group.remove();
        this.inflight.delete(group);
      };
    }, duration);
  },

  hit(route) {
    this.screen = (this.screen + 1) % SCREENS;
    if (this.phone) this.phone.dataset.screen = String(this.screen);

    const pulse = document.createElement("span");
    pulse.setAttribute("data-part", "pulse");
    pulse.style.left = `${route.end.x}px`;
    pulse.style.top = `${route.end.y}px`;
    pulse.addEventListener("animationend", () => pulse.remove());
    this.el.appendChild(pulse);
  },
};

export { PreviewsCommitGraph };
