/**
 * ShardingTimeline: plays the tests page's sharding illustration whenever it
 * scrolls into view.
 *
 * The bar fills and runner-dot blinks are CSS animations (routes/tests.css);
 * this hook only schedules them. On every play it walks each lane's bars in
 * order and hands them a duration and delay, so bars run back to back within
 * a lane while the four lanes run in parallel. Base timing comes from the
 * axis (72px = 5ms, scaled by --sharding-ms), then each bar gets a random
 * speed nudge and a short random pause before it, so no two lanes — even
 * ones with identical bars — move in lockstep or finish together. Each
 * runner's dot gets its own random blink period and phase, and stops
 * blinking when its lane's last bar completes.
 *
 * The story plays once: after the first entry the observer disconnects and
 * the finished chart stays put.
 */
const PX_PER_AXIS_MS = 72 / 5;

function between(min, max) {
  return min + Math.random() * (max - min);
}

const ShardingTimeline = {
  mounted() {
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          this.observer.disconnect();
          this.play();
        }
      },
      { threshold: 0.5 },
    );
    this.observer.observe(this.el);
  },

  destroyed() {
    if (this.observer) this.observer.disconnect();
  },

  play() {
    this.schedule();
    this.el.dataset.state = "running";
  },

  schedule() {
    const msPerAxisMs = parseFloat(getComputedStyle(this.el).getPropertyValue("--sharding-ms")) || 50;

    this.el.querySelectorAll('[data-part="lane"]').forEach((lane) => {
      let clock = 0;

      lane.querySelectorAll('[data-part="bar"]').forEach((bar) => {
        // Narrow viewports hide trailing bars in CSS; they shouldn't count
        // toward the lane's run time (and so the dot's blink).
        if (!bar.offsetParent) return;
        const width = parseFloat(bar.style.getPropertyValue("--bar-width")) || 0;
        const duration = (width / PX_PER_AXIS_MS) * msPerAxisMs * between(0.85, 1.2);
        clock += between(0, 140);
        bar.style.setProperty("--bar-delay", `${Math.round(clock)}ms`);
        bar.style.setProperty("--bar-duration", `${Math.round(duration)}ms`);
        clock += duration;
      });

      const period = between(320, 760);
      lane.style.setProperty("--blink-period", `${Math.round(period)}ms`);
      lane.style.setProperty("--blink-delay", `${Math.round(between(0, period))}ms`);
      lane.style.setProperty("--blink-count", (clock / period).toFixed(2));
    });
  },
};

export { ShardingTimeline };
