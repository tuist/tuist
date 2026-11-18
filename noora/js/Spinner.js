// <noora-spinner>: a solid arc that runs around a dim ring of dashes,
// covering them as it passes. It's quick all the way round, but never even:
// it works its way up one side, eases over the top, and is whipped down the
// other side and through the bottom.
//
// It's one continuous simulation of two bodies on the ring:
//
// - The head is pulled by gravity (downhill from the top) and by a magnet
//   just below the ring, whose pull sharpens near the bottom. Drag slows it,
//   and a motor of constant power drives it: the slower it goes, the harder
//   the motor pushes, so it keeps a brisk pace up the climb and never
//   stalls.
// - The tail feels the same gravity and magnet, and is tied to the head by a
//   soft, lightly damped spring, so the arc is elastic: it stretches when
//   the head falls away, then snaps back short, with a wobble.
//
// The motor's power drifts at random, so no two laps move alike, and nothing
// ever resets, so the motion never jumps.
//
// The simulation runs ahead of time, a chunk at a time, and each chunk plays
// as Web Animations: the rotation runs on the compositor, so it stays smooth
// on a busy page. Chunks are scheduled back to back on the document
// timeline, so they join without a seam. The markup (both rings) is rendered
// by Noora.Spinner; this element only animates it, so it needs no id and
// works inside any component.

const TAU = Math.PI * 2;

// Gravity, the magnet's strength, and its distance below the ring (in radii).
const GRAVITY = 50;
const MAGNET = 45;
const MAGNET_REACH = 1.35;

// The motor's mean power, how far it drifts, and its torque limit. Drag is
// proportional to speed.
const POWER = 750;
const POWER_DRIFT = 0.45;
const MAX_TORQUE = 400;
const DRAG = 4.5;

// The spring between head and tail: stiffness, damping, and the arc's length
// at rest and at its limits (radians).
const SPRING = 70;
const DAMPING = 5;
const ARC_REST = 0.9;
const ARC_MIN = 0.4;
const ARC_MAX = 3.6;

// Simulation steps per second, and how many steps make one keyframe (60/s).
const STEPS = 960;
const STEPS_PER_KEYFRAME = 16;
const CHUNK_SECONDS = 1;

// The pull along the ring at an angle (clockwise from the top): gravity plus
// the magnet.
const pull = (angle) => {
  const sin = Math.sin(angle);
  const distance = Math.hypot(sin, Math.cos(angle) + MAGNET_REACH);
  return GRAVITY * sin + (MAGNET * MAGNET_REACH * sin) / distance ** 3;
};

// The running simulation. `next(seconds)` advances it and returns that
// stretch of motion as keyframes for the rotation and the arc length.
export function createMotion(random = Math.random) {
  let head = 0.5;
  let headSpeed = 6;
  let tail = head - ARC_REST;
  let tailSpeed = 6;
  let power = POWER;
  let powerTarget = POWER;
  let untilDrift = 0;
  const dt = 1 / STEPS;

  const step = () => {
    // The motor's power eases toward a new random target every so often.
    untilDrift -= dt;
    if (untilDrift <= 0) {
      powerTarget = POWER * (1 + POWER_DRIFT * (random() * 2 - 1));
      untilDrift = 0.3 + 0.4 * random();
    }
    power += (powerTarget - power) * Math.min(1, dt * 6);

    const drive = Math.min(power / Math.max(headSpeed, 0.3), MAX_TORQUE);
    const headForce = pull(head) - DRAG * headSpeed + drive;
    const tailForce =
      pull(tail) -
      DRAG * tailSpeed +
      SPRING * (head - tail - ARC_REST) +
      DAMPING * (headSpeed - tailSpeed);

    headSpeed += headForce * dt;
    head += headSpeed * dt;
    tailSpeed += tailForce * dt;
    tail += tailSpeed * dt;

    // The arc can't fold up or wrap the ring.
    if (head - tail < ARC_MIN) {
      tail = head - ARC_MIN;
      tailSpeed = Math.min(tailSpeed, headSpeed);
    } else if (head - tail > ARC_MAX) {
      tail = head - ARC_MAX;
      tailSpeed = Math.max(tailSpeed, headSpeed);
    }
  };

  const frame = (origin, offset) => {
    const length = ((head - tail) / TAU) * 100;
    return {
      rotate: {
        transform: `rotate(${(((head - origin) / TAU) * 360).toFixed(3)}deg)`,
        offset,
      },
      stretch: {
        strokeDasharray: `${length.toFixed(3)} ${(100 - length).toFixed(3)}`,
        strokeDashoffset: length.toFixed(3),
        offset,
      },
    };
  };

  return {
    next(seconds = CHUNK_SECONDS) {
      const keyframes = Math.round((seconds * STEPS) / STEPS_PER_KEYFRAME);
      // Rotation is measured from the last whole turn, so the chunk starts
      // where the previous one ended.
      const origin = Math.floor(head / TAU) * TAU;
      const frames = [frame(origin, 0)];
      for (let k = 1; k <= keyframes; k++) {
        for (let i = 0; i < STEPS_PER_KEYFRAME; i++) step();
        frames.push(frame(origin, k / keyframes));
      }
      return {
        duration: seconds * 1000,
        rotate: frames.map((f) => f.rotate),
        stretch: frames.map((f) => f.stretch),
      };
    },
  };
}

const reducedMotion =
  typeof window !== "undefined" &&
  window.matchMedia?.("(prefers-reduced-motion: reduce)");

// A plain base where there's no DOM, so the physics can be tested without one.
const Base = typeof HTMLElement === "undefined" ? class {} : HTMLElement;

const now = () => document.timeline?.currentTime ?? performance.now();

class NooraSpinner extends Base {
  connectedCallback() {
    this.arc = this.querySelector('[data-part="arc"]');
    this.stroke = this.arc?.querySelector("circle");
    if (!this.stroke || !this.arc.animate) return;
    if (reducedMotion?.matches) {
      this.dataset.motion = "reduced";
      return;
    }
    this.motion = createMotion();
    this.running = true;
    this.start();
  }

  disconnectedCallback() {
    this.running = false;
    this.cancel(this.playing);
    this.cancel(this.queued);
  }

  // Plays one chunk now and queues the next to begin the instant it ends.
  start() {
    this.playing = this.chunk(now());
    this.queued = this.chunk(this.playing.end);
    this.playing.spin.onfinish = () => this.advance();
  }

  advance() {
    if (!this.running) return;
    const finished = this.playing;

    // After a long pause (a hidden tab), the queue is stale: start afresh.
    if (this.queued.end < now()) {
      this.cancel(this.queued);
      this.start();
    } else {
      this.playing = this.queued;
      this.queued = this.chunk(this.playing.end);
      this.playing.spin.onfinish = () => this.advance();
    }
    // The newer chunk is already in control, so dropping this one is unseen.
    this.cancel(finished);
  }

  chunk(startTime) {
    const { duration, rotate, stretch } = this.motion.next();
    const options = { duration, fill: "forwards" };
    const spin = this.arc.animate(rotate, options);
    const length = this.stroke.animate(stretch, options);
    spin.startTime = startTime;
    length.startTime = startTime;
    return { spin, length, end: startTime + duration };
  }

  cancel(chunk) {
    chunk?.spin.cancel();
    chunk?.length.cancel();
  }
}

if (typeof window !== "undefined" && !customElements.get("noora-spinner")) {
  customElements.define("noora-spinner", NooraSpinner);
}

export default NooraSpinner;
