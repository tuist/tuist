// @vitest-environment happy-dom
import { describe, it, expect } from "vitest";
import { bindScrollIndicator } from "./ScrollIndicator.js";

function setup(axis, options) {
  const viewport = document.createElement("div");
  const track = document.createElement("div");
  const thumb = document.createElement("div");
  track.appendChild(thumb);
  const horizontal = axis === "horizontal";
  const client = horizontal ? "clientWidth" : "clientHeight";
  const extent = horizontal ? "scrollWidth" : "scrollHeight";
  const position = horizontal ? "scrollLeft" : "scrollTop";
  Object.defineProperty(viewport, client, { value: 200, configurable: true });
  Object.defineProperty(viewport, extent, { value: 1000, configurable: true });
  Object.defineProperty(track, client, { value: 100 });
  let capture;
  thumb.setPointerCapture = (id) => {
    capture = id;
  };
  thumb.hasPointerCapture = (id) => capture === id;
  thumb.releasePointerCapture = () => {
    capture = null;
  };
  const pointer = (type, coordinate) =>
    thumb.dispatchEvent(
      new PointerEvent(type, {
        pointerId: 1,
        button: 0,
        [horizontal ? "clientX" : "clientY"]: coordinate,
      }),
    );
  return {
    viewport,
    track,
    thumb,
    position,
    extent,
    pointer,
    ...bindScrollIndicator(viewport, track, thumb, axis, options),
  };
}

describe("scroll indicators", () => {
  it("allows the table to drive updates only when its overlay is visible", () => {
    const bar = setup("horizontal", { autoUpdate: false });
    expect(bar.thumb.style.width).toBe("");
    bar.viewport.scrollLeft = 400;
    bar.viewport.dispatchEvent(new Event("scroll"));
    expect(bar.thumb.style.width).toBe("");
    bar.update();
    expect(bar.thumb.style.width).toBe("24px");
    expect(bar.thumb.style.transform).toBe("translateX(38px)");
    bar.destroy();
  });
  for (const axis of ["horizontal", "vertical"]) {
    it(`keeps the ${axis} thumb aligned with native scrolling and resizing`, () => {
      const bar = setup(axis);
      const size = axis === "horizontal" ? "width" : "height";
      const transform = axis === "horizontal" ? "X" : "Y";
      bar.viewport[bar.position] = 400;
      bar.viewport.dispatchEvent(new Event("scroll"));
      expect(bar.thumb.style[size]).toBe("24px");
      expect(bar.thumb.style.transform).toBe(`translate${transform}(38px)`);
      Object.defineProperty(bar.viewport, bar.extent, { value: 400 });
      bar.viewport[bar.position] = 200;
      bar.update();
      expect(bar.thumb.style[size]).toBe("50px");
      expect(bar.thumb.style.transform).toBe(`translate${transform}(50px)`);
      bar.destroy();
    });
    it(`drags the ${axis} thumb and stops on cancellation and cleanup`, () => {
      const bar = setup(axis);
      bar.pointer("pointerdown", 0);
      bar.pointer("pointermove", 38);
      expect(bar.viewport[bar.position]).toBe(400);
      bar.pointer("pointercancel", 38);
      bar.pointer("pointermove", 76);
      expect(bar.viewport[bar.position]).toBe(400);
      expect(bar.track.hasAttribute("data-dragging")).toBe(false);
      bar.destroy();
      bar.pointer("pointerdown", 0);
      bar.pointer("pointermove", 76);
      expect(bar.viewport[bar.position]).toBe(400);
    });
  }
});
