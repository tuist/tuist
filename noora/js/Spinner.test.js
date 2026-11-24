import { describe, expect, it } from "vitest";
import { createMotion } from "./Spinner.js";

const seeded = (seed = 1) => {
  let state = seed;
  return () => {
    state = (state * 16807) % 2147483647;
    return state / 2147483647;
  };
};

const angle = (keyframe) =>
  Number(keyframe.transform.match(/rotate\(([-\d.]+)deg\)/)[1]);
const length = (keyframe) => parseFloat(keyframe.strokeDasharray);

// Thirty seconds of motion as [angle within the turn, degrees moved, arc].
const sample = (seed) => {
  const motion = createMotion(seeded(seed));
  const frames = [];
  for (let chunk = 0; chunk < 30; chunk++) {
    const { rotate, stretch } = motion.next();
    for (let i = 1; i < rotate.length; i++) {
      frames.push({
        at: ((angle(rotate[i]) % 360) + 360) % 360,
        moved: angle(rotate[i]) - angle(rotate[i - 1]),
        arc: length(stretch[i]),
      });
    }
  }
  return frames.slice(180);
};

describe("createMotion", () => {
  it("continues from chunk to chunk without a jump in place or speed", () => {
    const motion = createMotion(seeded());
    let previous = motion.next();
    for (let chunk = 0; chunk < 20; chunk++) {
      const next = motion.next();
      const end = angle(previous.rotate.at(-1));
      const start = angle(next.rotate[0]);
      // Same place on the ring, whole turns apart.
      const apart = (((end - start) % 360) + 360) % 360;
      expect(Math.min(apart, 360 - apart)).toBeLessThan(0.05);

      // The speed changes across the seam no more than between any two
      // frames inside a chunk.
      const steps = next.rotate
        .slice(1)
        .map((frame, i) => angle(frame) - angle(next.rotate[i]));
      const sharpest = Math.max(
        ...steps.slice(1).map((step, i) => Math.abs(step - steps[i])),
      );
      const lastStep = end - angle(previous.rotate.at(-2));
      expect(Math.abs(steps[0] - lastStep)).toBeLessThanOrEqual(
        sharpest + 0.01,
      );
      expect(length(next.stretch[0])).toBeCloseTo(
        length(previous.stretch.at(-1)),
        2,
      );
      previous = next;
    }
  });

  it("always moves forward, easing over the top and whipping through the bottom", () => {
    const frames = sample(3);
    const speedNear = (center) => {
      const near = frames.filter((f) => Math.abs(f.at - center) < 25);
      return near.reduce((sum, f) => sum + f.moved, 0) / near.length;
    };

    expect(Math.min(...frames.map((f) => f.moved))).toBeGreaterThan(0);
    expect(speedNear(180)).toBeGreaterThan(speedNear(345) * 1.5);
    // Brisk even at its slowest: at least 4 radians a second.
    expect(Math.min(...frames.map((f) => f.moved))).toBeGreaterThan(
      ((4 / 60) * 180) / Math.PI,
    );
  });

  it("stretches the arc on the fall and keeps it within the ring", () => {
    const arcs = sample(5).map((f) => f.arc);

    expect(Math.min(...arcs)).toBeGreaterThan(4);
    expect(Math.max(...arcs)).toBeLessThan(58);
    expect(Math.max(...arcs)).toBeGreaterThan(Math.min(...arcs) * 2);
  });

  it("varies from lap to lap", () => {
    const frames = sample(7);
    const laps = [];
    let frameCount = 0;
    for (let i = 1; i < frames.length; i++) {
      frameCount++;
      if (frames[i].at < frames[i - 1].at) {
        laps.push(frameCount / 60);
        frameCount = 0;
      }
    }
    const whole = laps.slice(1);

    expect(Math.max(...whole)).toBeGreaterThan(Math.min(...whole) * 1.25);
    expect(Math.max(...whole)).toBeLessThan(0.9);
  });
});
