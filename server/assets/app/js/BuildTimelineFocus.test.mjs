import test from "node:test";
import assert from "node:assert/strict";
import { bindDragFocus } from "./BuildTimelineFocus.mjs";

function setup() {
  const element = new EventTarget();
  const captures = new Set();
  element.setPointerCapture = (id) => captures.add(id);
  element.hasPointerCapture = (id) => captures.has(id);
  element.releasePointerCapture = (id) => captures.delete(id);
  element.focus = () => {};
  const previews = [];
  const focused = [];
  const abort = new AbortController();
  const cancel = bindDragFocus(element, {
    geometry: () => ({ left: 100, width: 400, start: 20, span: 80 }),
    preview: (range) => previews.push(range),
    focus: (range) => focused.push(range),
    signal: abort.signal,
  });
  const dispatch = (type, clientX, properties = {}) => {
    const event = Object.assign(new Event(type, { cancelable: true }), {
      clientX,
      pointerId: 1,
      button: 0,
      ...properties,
    });
    element.dispatchEvent(event);
    return event;
  };
  return { dispatch, previews, focused, captures, cancel, abort };
}

test("drag previews an interval without zooming until release, then suppresses its click", () => {
  const { dispatch, previews, focused, captures } = setup();
  dispatch("pointerdown", 200);
  dispatch("pointermove", 400);
  assert.deepEqual(previews.at(-1), { start: 40, span: 40, left: 0.25, width: 0.5 });
  assert.equal(focused.length, 0);
  dispatch("pointerup", 400);
  assert.deepEqual(focused, [{ start: 40, span: 40 }]);
  assert.equal(previews.at(-1), null);
  assert.equal(captures.size, 0);
  assert.equal(dispatch("click", 400).defaultPrevented, true);
});

test("reverse and Option drags clamp to the existing viewport", () => {
  const { dispatch, focused } = setup();
  dispatch("pointerdown", 400, { altKey: true });
  dispatch("pointermove", -200);
  dispatch("pointerup", -200);
  assert.deepEqual(focused, [{ start: 20, span: 60 }]);
});

test("small pointer movements preserve ordinary step clicks", () => {
  const { dispatch, focused } = setup();
  dispatch("pointerdown", 200);
  dispatch("pointerup", 202);
  assert.equal(focused.length, 0);
  assert.equal(dispatch("click", 202).defaultPrevented, false);
});

test("Escape, pointer cancellation, lost capture, and range changes discard the selection", () => {
  for (const reason of ["escape", "pointercancel", "lostpointercapture", "range"]) {
    const { dispatch, focused, previews, cancel, captures } = setup();
    dispatch("pointerdown", 200);
    dispatch("pointermove", 400);
    if (reason === "escape") dispatch("keydown", 400, { key: "Escape" });
    else if (reason === "range") cancel();
    else dispatch(reason, 400);
    dispatch("pointerup", 400);
    assert.equal(focused.length, 0);
    assert.equal(previews.at(-1), null);
    assert.equal(captures.size, 0);
  }
});

test("secondary buttons and unrelated pointers do not select a range", () => {
  const { dispatch, previews, focused } = setup();
  dispatch("pointerdown", 200, { button: 2 });
  dispatch("pointermove", 400);
  assert.equal(previews.length, 0);
  dispatch("pointerdown", 200);
  dispatch("pointermove", 400, { pointerId: 2 });
  dispatch("pointerup", 400, { pointerId: 2 });
  assert.equal(focused.length, 0);
  dispatch("pointerup", 200);
  assert.equal(focused.length, 0);
});
