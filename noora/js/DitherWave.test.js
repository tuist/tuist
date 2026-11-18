// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import DitherWave from "./DitherWave.js";

let hook;

function fakeContext() {
  return {
    createImageData: (width, height) => ({
      width,
      height,
      data: new Uint8ClampedArray(width * height * 4),
    }),
    putImageData: vi.fn(),
  };
}

beforeEach(() => {
  globalThis.ResizeObserver = class {
    observe() {}
    disconnect() {}
  };
  globalThis.IntersectionObserver = class {
    observe() {}
    disconnect() {}
  };
  // Reduced motion: one static frame, no animation loop to clean up.
  window.matchMedia = () => ({
    matches: true,
    addEventListener() {},
    removeEventListener() {},
  });
});

afterEach(() => {
  hook?.destroyed();
  hook = undefined;
  document.body.innerHTML = "";
});

function mount(attributes) {
  document.body.innerHTML = `<div><canvas id="wave" ${attributes}></canvas></div>`;
  const el = document.getElementById("wave");
  const context = fakeContext();
  el.getContext = () => context;
  el.getBoundingClientRect = () => ({ width: 200, height: 40 });
  hook = { ...DitherWave, el };
  hook.mounted();
  return { el, context };
}

it("draws one pixel per dither cell, denser toward the bottom", () => {
  const { el, context } = mount('data-colors="--a,--b" data-pitch="2"');

  expect(el.width).toBe(100);
  expect(el.height).toBe(20);
  expect(context.putImageData).toHaveBeenCalled();

  const pixels = hook.image.data;
  const opaqueInRow = (y) => {
    let count = 0;
    for (let x = 0; x < 100; x++)
      if (pixels[(y * 100 + x) * 4 + 3] > 0) count++;
    return count;
  };
  expect(opaqueInRow(0)).toBeLessThan(opaqueInRow(19));
  expect(opaqueInRow(19)).toBeGreaterThan(0);
});

it("does nothing without a color ramp", () => {
  const { context } = mount("");

  expect(context.putImageData).not.toHaveBeenCalled();
});
