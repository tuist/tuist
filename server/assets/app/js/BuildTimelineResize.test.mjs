import test from "node:test";
import assert from "node:assert/strict";
import { bindInspectorResize } from "./BuildTimelineResize.mjs";

function setup() {
  const divider = new EventTarget();
  const attributes = new Map();
  const captures = new Set();
  divider.setAttribute = (name, value) => attributes.set(name, value);
  divider.removeAttribute = (name) => attributes.delete(name);
  divider.setPointerCapture = (id) => captures.add(id);
  divider.hasPointerCapture = (id) => captures.has(id);
  divider.releasePointerCapture = (id) => captures.delete(id);
  divider.focus = () => {};
  let available = 1000;
  let width;
  const abort = new AbortController();
  const update = bindInspectorResize(divider, {
    availableWidth: () => available,
    setWidth: (value) => {
      width = value;
    },
    signal: abort.signal,
  });
  const dispatch = (type, values = {}) => {
    const event = Object.assign(new Event(type, { cancelable: true }), {
      button: 0,
      pointerId: 1,
      clientX: 700,
      ...values,
    });
    divider.dispatchEvent(event);
    return event;
  };
  return {
    dispatch,
    attributes,
    captures,
    abort,
    width: () => width,
    resize: (value) => {
      available = value;
      update();
    },
  };
}

test("dragging left expands details and keeps room for the chart", () => {
  const view = setup();
  view.dispatch("pointerdown");
  view.dispatch("pointermove", { clientX: 500 });
  assert.equal(view.width(), 440);
  view.dispatch("pointermove", { clientX: -1000 });
  assert.equal(view.width(), 716);
  view.dispatch("pointerup");
  assert.equal(view.captures.size, 0);
  view.dispatch("pointermove", { clientX: 1000 });
  assert.equal(view.width(), 716);
  view.resize(600);
  assert.equal(view.width(), 316);
  view.resize(1000);
  assert.equal(view.width(), 716);
});

test("keyboard controls resize within limits and update accessible values", () => {
  const view = setup();
  assert.equal(view.dispatch("keydown", { key: "ArrowLeft" }).defaultPrevented, true);
  assert.equal(view.width(), 260);
  view.dispatch("keydown", { key: "Home" });
  assert.equal(view.width(), 180);
  view.dispatch("keydown", { key: "ArrowRight" });
  assert.equal(view.width(), 180);
  view.dispatch("keydown", { key: "End" });
  assert.equal(view.attributes.get("aria-valuenow"), 716);
  assert.equal(view.attributes.get("aria-valuemax"), 716);
});

test("Escape restores the previous width and teardown removes drag listeners", () => {
  const view = setup();
  view.dispatch("pointerdown");
  view.dispatch("pointermove", { clientX: 500, pointerId: 2 });
  assert.equal(view.width(), 240);
  view.dispatch("pointermove", { clientX: 500 });
  view.dispatch("keydown", { key: "Escape" });
  assert.equal(view.width(), 240);
  assert.equal(view.captures.size, 0);
  view.dispatch("pointerdown");
  view.abort.abort();
  view.dispatch("pointermove", { clientX: 300 });
  assert.equal(view.width(), 240);
  assert.equal(view.captures.size, 0);
});
