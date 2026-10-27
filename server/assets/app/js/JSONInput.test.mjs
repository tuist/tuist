import assert from "node:assert/strict";
import test from "node:test";
import JSONInput, { enhanceJSONInput } from "./JSONInput.mjs";

function fixture() {
  const source = '{"sub":"production"}';
  let highlight = { dataset: { source }, style: {} };
  const overlay = {
    hidden: true,
    style: {},
    querySelector: () => highlight,
  };
  const wrapper = {
    highlighted: false,
    querySelector: () => overlay,
    toggleAttribute(name, active) {
      this.highlighted = active;
    },
    removeAttribute() {
      this.highlighted = false;
    },
  };
  const textarea = Object.assign(new EventTarget(), {
    value: source,
    parentElement: wrapper,
    clientWidth: 240,
    clientHeight: 96,
    scrollTop: 0,
    scrollLeft: 0,
    selectionStart: 5,
    selectionEnd: 8,
  });
  let observer;
  class FakeResizeObserver {
    constructor(callback) {
      this.refresh = callback;
      observer = this;
    }
    observe(element) {
      this.element = element;
    }
    disconnect() {
      this.disconnected = true;
    }
  }
  return {
    textarea,
    wrapper,
    overlay,
    ResizeObserver: FakeResizeObserver,
    observer: () => observer,
    replaceHighlight(source) {
      highlight = source === null ? null : { dataset: { source }, style: {} };
    },
  };
}

function mount() {
  const state = fixture();
  return { ...state, input: enhanceJSONInput(state.textarea, state.ResizeObserver) };
}

test("enables only matching server highlighting without touching the native value or selection", () => {
  const { textarea, wrapper, overlay, input } = mount();
  assert.equal(wrapper.highlighted, true);
  assert.equal(overlay.hidden, false);
  assert.equal(overlay.style.width, "240px");
  assert.equal(overlay.style.height, "96px");
  input.refresh();
  assert.equal(textarea.value, '{"sub":"production"}');
  assert.equal(textarea.selectionStart, 5);
  assert.equal(textarea.selectionEnd, 8);
});

test("typing immediately falls back to plain text until the exact latest response arrives", () => {
  const { textarea, wrapper, overlay, input, replaceHighlight } = mount();
  textarea.value = '{"sub":"new';
  textarea.dispatchEvent(new Event("input"));
  assert.equal(wrapper.highlighted, false);
  assert.equal(overlay.hidden, true);
  replaceHighlight('{"sub":"n');
  input.refresh();
  assert.equal(wrapper.highlighted, false);
  replaceHighlight(textarea.value);
  input.refresh();
  assert.equal(wrapper.highlighted, true);
  assert.equal(overlay.hidden, false);
  assert.equal(textarea.value, '{"sub":"new');
});

test("missing or oversized highlighting leaves a readable native field", () => {
  const { wrapper, overlay, input, replaceHighlight } = mount();
  replaceHighlight(null);
  input.refresh();
  assert.equal(wrapper.highlighted, false);
  assert.equal(overlay.hidden, true);
});

test("IME composition never hides the native composing text", () => {
  const { textarea, wrapper, input, replaceHighlight } = mount();
  textarea.dispatchEvent(new Event("compositionstart"));
  assert.equal(wrapper.highlighted, false);
  textarea.value = '{"sub":"日本語"}';
  replaceHighlight(textarea.value);
  input.refresh();
  assert.equal(wrapper.highlighted, false);
  textarea.dispatchEvent(new Event("compositionend"));
  assert.equal(wrapper.highlighted, true);
});

test("tracks scrolling and resizing, including opening an initially collapsed field", () => {
  const { textarea, overlay, observer } = mount();
  textarea.scrollTop = 48;
  textarea.scrollLeft = 12;
  textarea.dispatchEvent(new Event("scroll"));
  assert.equal(overlay.querySelector().style.transform, "translate(-12px, -48px)");
  textarea.clientWidth = 0;
  textarea.clientHeight = 0;
  observer().refresh();
  textarea.clientWidth = 180;
  textarea.clientHeight = 144;
  observer().refresh();
  assert.equal(overlay.style.width, "180px");
  assert.equal(overlay.style.height, "144px");
  assert.equal(observer().element, textarea);
});

test("teardown removes listeners, disconnects observers and restores native text", () => {
  const { textarea, wrapper, overlay, input, observer, replaceHighlight } = mount();
  input.destroy();
  assert.equal(wrapper.highlighted, false);
  assert.equal(overlay.hidden, true);
  assert.equal(observer().disconnected, true);
  replaceHighlight(textarea.value);
  textarea.dispatchEvent(new Event("input"));
  textarea.dispatchEvent(new Event("scroll"));
  textarea.dispatchEvent(new Event("compositionend"));
  assert.equal(wrapper.highlighted, false);
});

test("a container update restores an overlay reset by a sibling field's LiveView patch", () => {
  const state = mount();
  state.input.destroy();
  const hook = { el: { querySelector: () => state.textarea } };
  JSONInput.mounted.call(hook);
  assert.equal(state.wrapper.highlighted, true);

  state.wrapper.removeAttribute("data-highlighted");
  state.overlay.hidden = true;
  state.overlay.style.width = "";
  JSONInput.updated.call(hook);
  assert.equal(state.wrapper.highlighted, true);
  assert.equal(state.overlay.hidden, false);
  assert.equal(state.overlay.style.width, `${state.textarea.clientWidth}px`);

  JSONInput.disconnected.call(hook);
  JSONInput.reconnected.call(hook);
  assert.equal(state.wrapper.highlighted, true);
  JSONInput.destroyed.call(hook);
});

test("LiveView disconnection and destruction restore readable text", () => {
  const state = mount();
  const hook = { el: state.textarea, jsonInput: state.input };
  JSONInput.disconnected.call(hook);
  assert.equal(state.wrapper.highlighted, false);
  assert.equal(hook.jsonInput, null);
  JSONInput.updated.call(hook);
  JSONInput.destroyed.call(hook);
  assert.equal(state.overlay.hidden, true);
});
