import test from "node:test";
import assert from "node:assert/strict";
import { bindPinchZoom } from "./BuildTimelineZoom.mjs";

function setup() {
  const element = new EventTarget();
  element.clientHeight = 400;
  const abort = new AbortController();
  const zooms = [];
  bindPinchZoom(element, (factor, event) => zooms.push({ factor, x: event.clientX }), abort.signal);
  const dispatch = (type, properties) => {
    const event = Object.assign(new Event(type, { cancelable: true }), properties);
    element.dispatchEvent(event);
    return event;
  };
  return { abort, zooms, dispatch };
}

test("trackpad pinch consumes browser zoom but leaves ordinary scrolling alone", () => {
  const { zooms, dispatch } = setup();
  assert.equal(dispatch("wheel", { deltaY: -20, ctrlKey: false }).defaultPrevented, false);
  assert.equal(zooms.length, 0);
  assert.equal(dispatch("wheel", { deltaY: -20, deltaMode: 0, ctrlKey: true, clientX: 320 }).defaultPrevented, true);
  assert.equal(zooms[0].x, 320);
  assert.ok(zooms[0].factor < 1);
  dispatch("wheel", { deltaY: 20, deltaMode: 0, ctrlKey: true });
  assert.ok(Math.abs(zooms[0].factor * zooms[1].factor - 1) < 1e-10);
});

test("WebKit pinch uses incremental scales without applying duplicate wheel events", () => {
  const { zooms, dispatch } = setup();
  dispatch("gesturestart", { scale: 1 });
  dispatch("gesturechange", { scale: 2, clientX: 150 });
  dispatch("wheel", { deltaY: -50, ctrlKey: true });
  dispatch("gesturechange", { scale: 4, clientX: 150 });
  dispatch("gesturechange", { scale: 0 });
  assert.deepEqual(zooms, [
    { factor: 0.5, x: 150 },
    { factor: 0.5, x: 150 },
  ]);
  dispatch("gestureend", {});
  dispatch("wheel", { deltaY: 10, ctrlKey: true });
  assert.equal(zooms.length, 3);
});

test("wheel units are normalized and listeners are removed when the hook is destroyed", () => {
  const { abort, zooms, dispatch } = setup();
  dispatch("wheel", { deltaY: 1, deltaMode: 1, ctrlKey: true });
  dispatch("wheel", { deltaY: 0.04, deltaMode: 2, ctrlKey: true });
  assert.equal(zooms[0].factor, zooms[1].factor);
  abort.abort();
  assert.equal(dispatch("wheel", { deltaY: 10, ctrlKey: true }).defaultPrevented, false);
  dispatch("gesturestart", { scale: 1 });
  dispatch("gesturechange", { scale: 2 });
  assert.equal(zooms.length, 2);
});
