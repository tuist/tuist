'use strict';

var domQuery = require('@zag-js/dom-query');
var utils = require('@zag-js/utils');

// src/index.ts

// src/frame-utils.ts
function getWindowFrames(win) {
  const frames = {
    each(cb) {
      for (let i = 0; i < win.frames?.length; i += 1) {
        const frame = win.frames[i];
        if (frame) cb(frame);
      }
    },
    addEventListener(event, listener, options) {
      frames.each((frame) => {
        try {
          frame.document.addEventListener(event, listener, options);
        } catch {
        }
      });
      return () => {
        try {
          frames.removeEventListener(event, listener, options);
        } catch {
        }
      };
    },
    removeEventListener(event, listener, options) {
      frames.each((frame) => {
        try {
          frame.document.removeEventListener(event, listener, options);
        } catch {
        }
      });
    }
  };
  return frames;
}
function getParentWindow(win) {
  const parent = win.frameElement != null ? win.parent : null;
  return {
    addEventListener: (event, listener, options) => {
      try {
        parent?.addEventListener(event, listener, options);
      } catch {
      }
      return () => {
        try {
          parent?.removeEventListener(event, listener, options);
        } catch {
        }
      };
    },
    removeEventListener: (event, listener, options) => {
      try {
        parent?.removeEventListener(event, listener, options);
      } catch {
      }
    }
  };
}

// src/index.ts
var POINTER_OUTSIDE_EVENT = "pointerdown.outside";
var FOCUS_OUTSIDE_EVENT = "focus.outside";
function isComposedPathFocusable(composedPath) {
  for (const node of composedPath) {
    if (domQuery.isHTMLElement(node) && domQuery.isFocusable(node)) return true;
  }
  return false;
}
var isPointerEvent = (event) => "clientY" in event;
function isEventPointWithin(node, event) {
  if (!isPointerEvent(event) || !node) return false;
  const rect = node.getBoundingClientRect();
  if (rect.width === 0 || rect.height === 0) return false;
  return rect.top <= event.clientY && event.clientY <= rect.top + rect.height && rect.left <= event.clientX && event.clientX <= rect.left + rect.width;
}
function isPointInRect(rect, point) {
  return rect.y <= point.y && point.y <= rect.y + rect.height && rect.x <= point.x && point.x <= rect.x + rect.width;
}
function isEventWithinScrollbar(event, ancestor) {
  if (!ancestor || !isPointerEvent(event)) return false;
  const isScrollableY = ancestor.scrollHeight > ancestor.clientHeight;
  const onScrollbarY = isScrollableY && event.clientX > ancestor.offsetLeft + ancestor.clientWidth;
  const isScrollableX = ancestor.scrollWidth > ancestor.clientWidth;
  const onScrollbarX = isScrollableX && event.clientY > ancestor.offsetTop + ancestor.clientHeight;
  const rect = {
    x: ancestor.offsetLeft,
    y: ancestor.offsetTop,
    width: ancestor.clientWidth + (isScrollableY ? 16 : 0),
    height: ancestor.clientHeight + (isScrollableX ? 16 : 0)
  };
  const point = {
    x: event.clientX,
    y: event.clientY
  };
  if (!isPointInRect(rect, point)) return false;
  return onScrollbarY || onScrollbarX;
}
function trackInteractOutsideImpl(node, options) {
  const { exclude, onFocusOutside, onPointerDownOutside, onInteractOutside, defer } = options;
  if (!node) return;
  const doc = domQuery.getDocument(node);
  const win = domQuery.getWindow(node);
  const frames = getWindowFrames(win);
  const parentWin = getParentWindow(win);
  function isEventOutside(event, target) {
    if (!domQuery.isHTMLElement(target)) return false;
    if (!target.isConnected) return false;
    if (domQuery.contains(node, target)) return false;
    if (isEventPointWithin(node, event)) return false;
    const triggerEl = doc.querySelector(`[aria-controls="${node.id}"]`);
    if (triggerEl) {
      const triggerAncestor = domQuery.getNearestOverflowAncestor(triggerEl);
      if (isEventWithinScrollbar(event, triggerAncestor)) return false;
    }
    const nodeAncestor = domQuery.getNearestOverflowAncestor(node);
    if (isEventWithinScrollbar(event, nodeAncestor)) return false;
    return !exclude?.(target);
  }
  const pointerdownCleanups = /* @__PURE__ */ new Set();
  const isInShadowRoot = domQuery.isShadowRoot(node?.getRootNode());
  function onPointerDown(event) {
    function handler(clickEvent) {
      const func = defer && !domQuery.isTouchDevice() ? domQuery.raf : (v) => v();
      const evt = clickEvent ?? event;
      const composedPath = evt?.composedPath?.() ?? [evt?.target];
      func(() => {
        const target = isInShadowRoot ? composedPath[0] : domQuery.getEventTarget(event);
        if (!node || !isEventOutside(event, target)) return;
        if (onPointerDownOutside || onInteractOutside) {
          const handler2 = utils.callAll(onPointerDownOutside, onInteractOutside);
          node.addEventListener(POINTER_OUTSIDE_EVENT, handler2, { once: true });
        }
        fireCustomEvent(node, POINTER_OUTSIDE_EVENT, {
          bubbles: false,
          cancelable: true,
          detail: {
            originalEvent: evt,
            contextmenu: domQuery.isContextMenuEvent(evt),
            focusable: isComposedPathFocusable(composedPath),
            target
          }
        });
      });
    }
    if (event.pointerType === "touch") {
      pointerdownCleanups.forEach((fn) => fn());
      pointerdownCleanups.add(domQuery.addDomEvent(doc, "click", handler, { once: true }));
      pointerdownCleanups.add(parentWin.addEventListener("click", handler, { once: true }));
      pointerdownCleanups.add(frames.addEventListener("click", handler, { once: true }));
    } else {
      handler();
    }
  }
  const cleanups = /* @__PURE__ */ new Set();
  const timer = setTimeout(() => {
    cleanups.add(domQuery.addDomEvent(doc, "pointerdown", onPointerDown, true));
    cleanups.add(parentWin.addEventListener("pointerdown", onPointerDown, true));
    cleanups.add(frames.addEventListener("pointerdown", onPointerDown, true));
  }, 0);
  function onFocusin(event) {
    const func = defer ? domQuery.raf : (v) => v();
    func(() => {
      const target = domQuery.getEventTarget(event);
      if (!node || !isEventOutside(event, target)) return;
      if (onFocusOutside || onInteractOutside) {
        const handler = utils.callAll(onFocusOutside, onInteractOutside);
        node.addEventListener(FOCUS_OUTSIDE_EVENT, handler, { once: true });
      }
      fireCustomEvent(node, FOCUS_OUTSIDE_EVENT, {
        bubbles: false,
        cancelable: true,
        detail: {
          originalEvent: event,
          contextmenu: false,
          focusable: domQuery.isFocusable(target),
          target
        }
      });
    });
  }
  if (!domQuery.isTouchDevice()) {
    cleanups.add(domQuery.addDomEvent(doc, "focusin", onFocusin, true));
    cleanups.add(parentWin.addEventListener("focusin", onFocusin, true));
    cleanups.add(frames.addEventListener("focusin", onFocusin, true));
  }
  return () => {
    clearTimeout(timer);
    pointerdownCleanups.forEach((fn) => fn());
    cleanups.forEach((fn) => fn());
  };
}
function trackInteractOutside(nodeOrFn, options) {
  const { defer } = options;
  const func = defer ? domQuery.raf : (v) => v();
  const cleanups = [];
  cleanups.push(
    func(() => {
      const node = typeof nodeOrFn === "function" ? nodeOrFn() : nodeOrFn;
      cleanups.push(trackInteractOutsideImpl(node, options));
    })
  );
  return () => {
    cleanups.forEach((fn) => fn?.());
  };
}
function fireCustomEvent(el, type, init) {
  const win = el.ownerDocument.defaultView || window;
  const event = new win.CustomEvent(type, init);
  return el.dispatchEvent(event);
}

exports.trackInteractOutside = trackInteractOutside;
