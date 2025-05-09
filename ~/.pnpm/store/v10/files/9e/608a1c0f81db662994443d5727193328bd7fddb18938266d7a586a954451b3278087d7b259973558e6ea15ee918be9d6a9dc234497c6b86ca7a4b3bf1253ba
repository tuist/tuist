'use strict';

// src/caret.ts
function isCaretAtStart(input) {
  if (!input) return false;
  try {
    return input.selectionStart === 0 && input.selectionEnd === 0;
  } catch {
    return input.value === "";
  }
}
function setCaretToEnd(input) {
  if (!input) return;
  const start = input.selectionStart ?? 0;
  const end = input.selectionEnd ?? 0;
  if (Math.abs(end - start) !== 0) return;
  if (start !== 0) return;
  input.setSelectionRange(input.value.length, input.value.length);
}

// src/shared.ts
var clamp = (value) => Math.max(0, Math.min(1, value));
var wrap = (v, idx) => {
  return v.map((_, index) => v[(Math.max(idx, 0) + index) % v.length]);
};
var pipe = (...fns) => (arg) => fns.reduce((acc, fn) => fn(acc), arg);
var noop = () => void 0;
var isObject = (v) => typeof v === "object" && v !== null;
var MAX_Z_INDEX = 2147483647;
var dataAttr = (guard) => guard ? "" : void 0;
var ariaAttr = (guard) => guard ? "true" : void 0;

// src/node.ts
var ELEMENT_NODE = 1;
var DOCUMENT_NODE = 9;
var DOCUMENT_FRAGMENT_NODE = 11;
var isHTMLElement = (el) => isObject(el) && el.nodeType === ELEMENT_NODE && typeof el.nodeName === "string";
var isDocument = (el) => isObject(el) && el.nodeType === DOCUMENT_NODE;
var isWindow = (el) => isObject(el) && el === el.window;
var isVisualViewport = (el) => isObject(el) && el.constructor.name === "VisualViewport";
var getNodeName = (node) => {
  if (isHTMLElement(node)) return node.localName || "";
  return "#document";
};
function isRootElement(node) {
  return ["html", "body", "#document"].includes(getNodeName(node));
}
var isNode = (el) => isObject(el) && el.nodeType !== void 0;
var isShadowRoot = (el) => isNode(el) && el.nodeType === DOCUMENT_FRAGMENT_NODE && "host" in el;
var isInputElement = (el) => isHTMLElement(el) && el.localName === "input";
var isAnchorElement = (el) => !!el?.matches("a[href]");
var isElementVisible = (el) => {
  if (!isHTMLElement(el)) return false;
  return el.offsetWidth > 0 || el.offsetHeight > 0 || el.getClientRects().length > 0;
};
var TEXTAREA_SELECT_REGEX = /(textarea|select)/;
function isEditableElement(el) {
  if (el == null || !isHTMLElement(el)) return false;
  try {
    return isInputElement(el) && el.selectionStart != null || TEXTAREA_SELECT_REGEX.test(el.localName) || el.isContentEditable || el.getAttribute("contenteditable") === "true" || el.getAttribute("contenteditable") === "";
  } catch {
    return false;
  }
}
function contains(parent, child) {
  if (!parent || !child) return false;
  if (!isHTMLElement(parent) || !isHTMLElement(child)) return false;
  const rootNode = child.getRootNode?.();
  if (parent === child) return true;
  if (parent.contains(child)) return true;
  if (rootNode && isShadowRoot(rootNode)) {
    let next = child;
    while (next) {
      if (parent === next) return true;
      next = next.parentNode || next.host;
    }
  }
  return false;
}
function getDocument(el) {
  if (isDocument(el)) return el;
  if (isWindow(el)) return el.document;
  return el?.ownerDocument ?? document;
}
function getDocumentElement(el) {
  return getDocument(el).documentElement;
}
function getWindow(el) {
  if (isShadowRoot(el)) return getWindow(el.host);
  if (isDocument(el)) return el.defaultView ?? window;
  if (isHTMLElement(el)) return el.ownerDocument?.defaultView ?? window;
  return window;
}
function getActiveElement(rootNode) {
  let activeElement = rootNode.activeElement;
  while (activeElement?.shadowRoot) {
    const el = activeElement.shadowRoot.activeElement;
    if (el === activeElement) break;
    else activeElement = el;
  }
  return activeElement;
}
function getParentNode(node) {
  if (getNodeName(node) === "html") return node;
  const result = node.assignedSlot || node.parentNode || isShadowRoot(node) && node.host || getDocumentElement(node);
  return isShadowRoot(result) ? result.host : result;
}

// src/computed-style.ts
var styleCache = /* @__PURE__ */ new WeakMap();
function getComputedStyle(el) {
  if (!styleCache.has(el)) {
    styleCache.set(el, getWindow(el).getComputedStyle(el));
  }
  return styleCache.get(el);
}

// src/data-url.ts
function getDataUrl(svg, opts) {
  const { type, quality = 0.92, background } = opts;
  if (!svg) throw new Error("[zag-js > getDataUrl]: Could not find the svg element");
  const win = getWindow(svg);
  const doc = win.document;
  const svgBounds = svg.getBoundingClientRect();
  const svgClone = svg.cloneNode(true);
  if (!svgClone.hasAttribute("viewBox")) {
    svgClone.setAttribute("viewBox", `0 0 ${svgBounds.width} ${svgBounds.height}`);
  }
  const serializer = new win.XMLSerializer();
  const source = '<?xml version="1.0" standalone="no"?>\r\n' + serializer.serializeToString(svgClone);
  const svgString = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(source);
  if (type === "image/svg+xml") {
    return Promise.resolve(svgString).then((str) => {
      svgClone.remove();
      return str;
    });
  }
  const dpr = win.devicePixelRatio || 1;
  const canvas = doc.createElement("canvas");
  const image = new win.Image();
  image.src = svgString;
  canvas.width = svgBounds.width * dpr;
  canvas.height = svgBounds.height * dpr;
  const context = canvas.getContext("2d");
  if (type === "image/jpeg" || background) {
    context.fillStyle = background || "white";
    context.fillRect(0, 0, canvas.width, canvas.height);
  }
  return new Promise((resolve) => {
    image.onload = () => {
      context?.drawImage(image, 0, 0, canvas.width, canvas.height);
      resolve(canvas.toDataURL(type, quality));
      svgClone.remove();
    };
  });
}

// src/platform.ts
var isDom = () => typeof document !== "undefined";
function getPlatform() {
  const agent = navigator.userAgentData;
  return agent?.platform ?? navigator.platform;
}
function getUserAgent() {
  const ua2 = navigator.userAgentData;
  if (ua2 && Array.isArray(ua2.brands)) {
    return ua2.brands.map(({ brand, version }) => `${brand}/${version}`).join(" ");
  }
  return navigator.userAgent;
}
var pt = (v) => isDom() && v.test(getPlatform());
var ua = (v) => isDom() && v.test(getUserAgent());
var vn = (v) => isDom() && v.test(navigator.vendor);
var isTouchDevice = () => isDom() && !!navigator.maxTouchPoints;
var isIPhone = () => pt(/^iPhone/i);
var isIPad = () => pt(/^iPad/i) || isMac() && navigator.maxTouchPoints > 1;
var isIos = () => isIPhone() || isIPad();
var isApple = () => isMac() || isIos();
var isMac = () => pt(/^Mac/i);
var isSafari = () => isApple() && vn(/apple/i);
var isFirefox = () => ua(/Firefox/i);
var isChrome = () => ua(/Chrome/i);
var isWebKit = () => ua(/AppleWebKit/i) && !isChrome();
var isAndroid = () => ua(/Android/i);

// src/event.ts
function getBeforeInputValue(event) {
  const { selectionStart, selectionEnd, value } = event.currentTarget;
  return value.slice(0, selectionStart) + event.data + value.slice(selectionEnd);
}
function getComposedPath(event) {
  return event.composedPath?.() ?? event.nativeEvent?.composedPath?.();
}
function getEventTarget(event) {
  const composedPath = getComposedPath(event);
  return composedPath?.[0] ?? event.target;
}
var isSelfTarget = (event) => {
  return contains(event.currentTarget, getEventTarget(event));
};
function isOpeningInNewTab(event) {
  const element = event.currentTarget;
  if (!element) return false;
  const isAppleDevice = isApple();
  if (isAppleDevice && !event.metaKey) return false;
  if (!isAppleDevice && !event.ctrlKey) return false;
  const localName = element.localName;
  if (localName === "a") return true;
  if (localName === "button" && element.type === "submit") return true;
  if (localName === "input" && element.type === "submit") return true;
  return false;
}
function isDownloadingEvent(event) {
  const element = event.currentTarget;
  if (!element) return false;
  const localName = element.localName;
  if (!event.altKey) return false;
  if (localName === "a") return true;
  if (localName === "button" && element.type === "submit") return true;
  if (localName === "input" && element.type === "submit") return true;
  return false;
}
function isComposingEvent(event) {
  return getNativeEvent(event).isComposing || event.keyCode === 229;
}
function isKeyboardClick(e) {
  return e.detail === 0 || e.clientX === 0 && e.clientY === 0;
}
function isCtrlOrMetaKey(e) {
  if (isMac()) return e.metaKey;
  return e.ctrlKey;
}
function isPrintableKey(e) {
  return e.key.length === 1 && !e.ctrlKey && !e.metaKey;
}
function isVirtualPointerEvent(e) {
  return e.width === 0 && e.height === 0 || e.width === 1 && e.height === 1 && e.pressure === 0 && e.detail === 0 && e.pointerType === "mouse";
}
function isVirtualClick(e) {
  if (e.mozInputSource === 0 && e.isTrusted) return true;
  if (isAndroid() && e.pointerType) {
    return e.type === "click" && e.buttons === 1;
  }
  return e.detail === 0 && !e.pointerType;
}
var isLeftClick = (e) => e.button === 0;
var isContextMenuEvent = (e) => {
  return e.button === 2 || isMac() && e.ctrlKey && e.button === 0;
};
var isModifierKey = (e) => e.ctrlKey || e.altKey || e.metaKey;
var isTouchEvent = (event) => "touches" in event && event.touches.length > 0;
var keyMap = {
  Up: "ArrowUp",
  Down: "ArrowDown",
  Esc: "Escape",
  " ": "Space",
  ",": "Comma",
  Left: "ArrowLeft",
  Right: "ArrowRight"
};
var rtlKeyMap = {
  ArrowLeft: "ArrowRight",
  ArrowRight: "ArrowLeft"
};
function getEventKey(event, options = {}) {
  const { dir = "ltr", orientation = "horizontal" } = options;
  let key = event.key;
  key = keyMap[key] ?? key;
  const isRtl = dir === "rtl" && orientation === "horizontal";
  if (isRtl && key in rtlKeyMap) key = rtlKeyMap[key];
  return key;
}
function getNativeEvent(event) {
  return event.nativeEvent ?? event;
}
var pageKeys = /* @__PURE__ */ new Set(["PageUp", "PageDown"]);
var arrowKeys = /* @__PURE__ */ new Set(["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"]);
function getEventStep(event) {
  if (event.ctrlKey || event.metaKey) {
    return 0.1;
  } else {
    const isPageKey = pageKeys.has(event.key);
    const isSkipKey = isPageKey || event.shiftKey && arrowKeys.has(event.key);
    return isSkipKey ? 10 : 1;
  }
}
function getEventPoint(event, type = "client") {
  const point = isTouchEvent(event) ? event.touches[0] || event.changedTouches[0] : event;
  return { x: point[`${type}X`], y: point[`${type}Y`] };
}
var addDomEvent = (target, eventName, handler, options) => {
  const node = typeof target === "function" ? target() : target;
  node?.addEventListener(eventName, handler, options);
  return () => {
    node?.removeEventListener(eventName, handler, options);
  };
};

// src/form.ts
function getDescriptor(el, options) {
  const { type = "HTMLInputElement", property = "value" } = options;
  const proto = getWindow(el)[type].prototype;
  return Object.getOwnPropertyDescriptor(proto, property) ?? {};
}
function getElementType(el) {
  if (el.localName === "input") return "HTMLInputElement";
  if (el.localName === "textarea") return "HTMLTextAreaElement";
  if (el.localName === "select") return "HTMLSelectElement";
}
function setElementValue(el, value, property = "value") {
  if (!el) return;
  const type = getElementType(el);
  if (type) {
    const descriptor = getDescriptor(el, { type, property });
    descriptor.set?.call(el, value);
  }
  el.setAttribute(property, value);
}
function setElementChecked(el, checked) {
  if (!el) return;
  const descriptor = getDescriptor(el, { type: "HTMLInputElement", property: "checked" });
  descriptor.set?.call(el, checked);
  if (checked) el.setAttribute("checked", "");
  else el.removeAttribute("checked");
}
function dispatchInputValueEvent(el, options) {
  const { value, bubbles = true } = options;
  if (!el) return;
  const win = getWindow(el);
  if (!(el instanceof win.HTMLInputElement)) return;
  setElementValue(el, `${value}`);
  el.dispatchEvent(new win.Event("input", { bubbles }));
}
function dispatchInputCheckedEvent(el, options) {
  const { checked, bubbles = true } = options;
  if (!el) return;
  const win = getWindow(el);
  if (!(el instanceof win.HTMLInputElement)) return;
  setElementChecked(el, checked);
  el.dispatchEvent(new win.Event("click", { bubbles }));
}
function getClosestForm(el) {
  return isFormElement(el) ? el.form : el.closest("form");
}
function isFormElement(el) {
  return el.matches("textarea, input, select, button");
}
function trackFormReset(el, callback) {
  if (!el) return;
  const form = getClosestForm(el);
  const onReset = (e) => {
    if (e.defaultPrevented) return;
    callback();
  };
  form?.addEventListener("reset", onReset, { passive: true });
  return () => form?.removeEventListener("reset", onReset);
}
function trackFieldsetDisabled(el, callback) {
  const fieldset = el?.closest("fieldset");
  if (!fieldset) return;
  callback(fieldset.disabled);
  const win = getWindow(fieldset);
  const obs = new win.MutationObserver(() => callback(fieldset.disabled));
  obs.observe(fieldset, {
    attributes: true,
    attributeFilter: ["disabled"]
  });
  return () => obs.disconnect();
}
function trackFormControl(el, options) {
  if (!el) return;
  const { onFieldsetDisabledChange, onFormReset } = options;
  const cleanups = [trackFormReset(el, onFormReset), trackFieldsetDisabled(el, onFieldsetDisabledChange)];
  return () => cleanups.forEach((cleanup) => cleanup?.());
}

// src/tabbable.ts
var isFrame = (el) => isHTMLElement(el) && el.tagName === "IFRAME";
var hasTabIndex = (el) => !Number.isNaN(parseInt(el.getAttribute("tabindex") || "0", 10));
var hasNegativeTabIndex = (el) => parseInt(el.getAttribute("tabindex") || "0", 10) < 0;
var focusableSelector = "input:not([type='hidden']):not([disabled]), select:not([disabled]), textarea:not([disabled]), a[href], button:not([disabled]), [tabindex], iframe, object, embed, area[href], audio[controls], video[controls], [contenteditable]:not([contenteditable='false']), details > summary:first-of-type";
var getFocusables = (container, includeContainer = false) => {
  if (!container) return [];
  const elements = Array.from(container.querySelectorAll(focusableSelector));
  const include = includeContainer == true || includeContainer == "if-empty" && elements.length === 0;
  if (include && isHTMLElement(container) && isFocusable(container)) {
    elements.unshift(container);
  }
  const focusableElements = elements.filter(isFocusable);
  focusableElements.forEach((element, i) => {
    if (isFrame(element) && element.contentDocument) {
      const frameBody = element.contentDocument.body;
      focusableElements.splice(i, 1, ...getFocusables(frameBody));
    }
  });
  return focusableElements;
};
function isFocusable(element) {
  if (!element || element.closest("[inert]")) return false;
  return element.matches(focusableSelector) && isElementVisible(element);
}
function getFirstFocusable(container, includeContainer) {
  const [first] = getFocusables(container, includeContainer);
  return first || null;
}
function getTabbables(container, includeContainer) {
  if (!container) return [];
  const elements = Array.from(container.querySelectorAll(focusableSelector));
  const tabbableElements = elements.filter(isTabbable);
  if (includeContainer && isTabbable(container)) {
    tabbableElements.unshift(container);
  }
  tabbableElements.forEach((element, i) => {
    if (isFrame(element) && element.contentDocument) {
      const frameBody = element.contentDocument.body;
      const allFrameTabbable = getTabbables(frameBody);
      tabbableElements.splice(i, 1, ...allFrameTabbable);
    }
  });
  if (!tabbableElements.length && includeContainer) {
    return elements;
  }
  return tabbableElements;
}
function isTabbable(el) {
  if (el != null && el.tabIndex > 0) return true;
  return isFocusable(el) && !hasNegativeTabIndex(el);
}
function getFirstTabbable(container, includeContainer) {
  const [first] = getTabbables(container, includeContainer);
  return first || null;
}
function getLastTabbable(container, includeContainer) {
  const elements = getTabbables(container, includeContainer);
  return elements[elements.length - 1] || null;
}
function getTabbableEdges(container, includeContainer) {
  const elements = getTabbables(container, includeContainer);
  const first = elements[0] || null;
  const last = elements[elements.length - 1] || null;
  return [first, last];
}
function getNextTabbable(container, current) {
  const tabbables = getTabbables(container);
  const doc = container?.ownerDocument || document;
  const currentElement = current ?? doc.activeElement;
  if (!currentElement) return null;
  const index = tabbables.indexOf(currentElement);
  return tabbables[index + 1] || null;
}
function getTabIndex(node) {
  if (node.tabIndex < 0) {
    if ((/^(audio|video|details)$/.test(node.localName) || isEditableElement(node)) && !hasTabIndex(node)) {
      return 0;
    }
  }
  return node.tabIndex;
}

// src/initial-focus.ts
function getInitialFocus(options) {
  const { root, getInitialEl, filter, enabled = true } = options;
  if (!enabled) return;
  let node = null;
  node || (node = typeof getInitialEl === "function" ? getInitialEl() : getInitialEl);
  node || (node = root?.querySelector("[data-autofocus],[autofocus]"));
  if (!node) {
    const tabbables = getTabbables(root);
    node = filter ? tabbables.filter(filter)[0] : tabbables[0];
  }
  return node || root || void 0;
}
function isValidTabEvent(event) {
  const container = event.currentTarget;
  if (!container) return false;
  const [firstTabbable, lastTabbable] = getTabbableEdges(container);
  const doc = container.ownerDocument || document;
  if (doc.activeElement === firstTabbable && event.shiftKey) return false;
  if (doc.activeElement === lastTabbable && !event.shiftKey) return false;
  if (!firstTabbable && !lastTabbable) return false;
  return true;
}

// src/raf.ts
function nextTick(fn) {
  const set = /* @__PURE__ */ new Set();
  function raf2(fn2) {
    const id = globalThis.requestAnimationFrame(fn2);
    set.add(() => globalThis.cancelAnimationFrame(id));
  }
  raf2(() => raf2(fn));
  return function cleanup() {
    set.forEach((fn2) => fn2());
  };
}
function raf(fn) {
  let cleanup;
  const id = globalThis.requestAnimationFrame(() => {
    cleanup = fn();
  });
  return () => {
    globalThis.cancelAnimationFrame(id);
    cleanup?.();
  };
}
function queueBeforeEvent(el, type, cb) {
  const cancelTimer = raf(() => {
    el.removeEventListener(type, exec, true);
    cb();
  });
  const exec = () => {
    cancelTimer();
    cb();
  };
  el.addEventListener(type, exec, { once: true, capture: true });
  return cancelTimer;
}

// src/mutation-observer.ts
function observeAttributesImpl(node, options) {
  if (!node) return;
  const { attributes, callback: fn } = options;
  const win = node.ownerDocument.defaultView || window;
  const obs = new win.MutationObserver((changes) => {
    for (const change of changes) {
      if (change.type === "attributes" && change.attributeName && attributes.includes(change.attributeName)) {
        fn(change);
      }
    }
  });
  obs.observe(node, { attributes: true, attributeFilter: attributes });
  return () => obs.disconnect();
}
function observeAttributes(nodeOrFn, options) {
  const { defer } = options;
  const func = defer ? raf : (v) => v();
  const cleanups = [];
  cleanups.push(
    func(() => {
      const node = typeof nodeOrFn === "function" ? nodeOrFn() : nodeOrFn;
      cleanups.push(observeAttributesImpl(node, options));
    })
  );
  return () => {
    cleanups.forEach((fn) => fn?.());
  };
}
function observeChildrenImpl(node, options) {
  const { callback: fn } = options;
  if (!node) return;
  const win = node.ownerDocument.defaultView || window;
  const obs = new win.MutationObserver(fn);
  obs.observe(node, { childList: true, subtree: true });
  return () => obs.disconnect();
}
function observeChildren(nodeOrFn, options) {
  const { defer } = options;
  const func = defer ? raf : (v) => v();
  const cleanups = [];
  cleanups.push(
    func(() => {
      const node = typeof nodeOrFn === "function" ? nodeOrFn() : nodeOrFn;
      cleanups.push(observeChildrenImpl(node, options));
    })
  );
  return () => {
    cleanups.forEach((fn) => fn?.());
  };
}

// src/navigate.ts
function clickIfLink(el) {
  const click = () => el.click();
  if (isFirefox()) {
    queueBeforeEvent(el, "keyup", click);
  } else {
    queueMicrotask(click);
  }
}

// src/overflow.ts
function getNearestOverflowAncestor(el) {
  const parentNode = getParentNode(el);
  if (isRootElement(parentNode)) return getDocument(parentNode).body;
  if (isHTMLElement(parentNode) && isOverflowElement(parentNode)) return parentNode;
  return getNearestOverflowAncestor(parentNode);
}
function getOverflowAncestors(el, list = []) {
  const scrollableAncestor = getNearestOverflowAncestor(el);
  const isBody = scrollableAncestor === el.ownerDocument.body;
  const win = getWindow(scrollableAncestor);
  if (isBody) {
    return list.concat(win, win.visualViewport || [], isOverflowElement(scrollableAncestor) ? scrollableAncestor : []);
  }
  return list.concat(scrollableAncestor, getOverflowAncestors(scrollableAncestor, []));
}
var getElementRect = (el) => {
  if (isHTMLElement(el)) return el.getBoundingClientRect();
  if (isVisualViewport(el)) return { top: 0, left: 0, bottom: el.height, right: el.width };
  return { top: 0, left: 0, bottom: el.innerHeight, right: el.innerWidth };
};
function isInView(el, ancestor) {
  if (!isHTMLElement(el)) return true;
  const ancestorRect = getElementRect(ancestor);
  const elRect = el.getBoundingClientRect();
  return elRect.top >= ancestorRect.top && elRect.left >= ancestorRect.left && elRect.bottom <= ancestorRect.bottom && elRect.right <= ancestorRect.right;
}
var OVERFLOW_RE = /auto|scroll|overlay|hidden|clip/;
function isOverflowElement(el) {
  const win = getWindow(el);
  const { overflow, overflowX, overflowY, display } = win.getComputedStyle(el);
  return OVERFLOW_RE.test(overflow + overflowY + overflowX) && !["inline", "contents"].includes(display);
}
function isScrollable(el) {
  return el.scrollHeight > el.clientHeight || el.scrollWidth > el.clientWidth;
}
function scrollIntoView(el, options) {
  const { rootEl, ...scrollOptions } = options || {};
  if (!el || !rootEl) return;
  if (!isOverflowElement(rootEl) || !isScrollable(rootEl)) return;
  el.scrollIntoView(scrollOptions);
}
function getScrollPosition(element) {
  if (isHTMLElement(element)) {
    return { scrollLeft: element.scrollLeft, scrollTop: element.scrollTop };
  }
  return { scrollLeft: element.scrollX, scrollTop: element.scrollY };
}

// src/point.ts
function getRelativePoint(point, element) {
  const { left, top, width, height } = element.getBoundingClientRect();
  const offset = { x: point.x - left, y: point.y - top };
  const percent = { x: clamp(offset.x / width), y: clamp(offset.y / height) };
  function getPercentValue(options = {}) {
    const { dir = "ltr", orientation = "horizontal", inverted } = options;
    const invertX = typeof inverted === "object" ? inverted.x : inverted;
    const invertY = typeof inverted === "object" ? inverted.y : inverted;
    if (orientation === "horizontal") {
      return dir === "rtl" || invertX ? 1 - percent.x : percent.x;
    }
    return invertY ? 1 - percent.y : percent.y;
  }
  return { offset, percent, getPercentValue };
}

// src/pointer-lock.ts
function requestPointerLock(doc, fn) {
  const body = doc.body;
  const supported = "pointerLockElement" in doc || "mozPointerLockElement" in doc;
  const isLocked = () => !!doc.pointerLockElement;
  function onPointerChange() {
    fn?.(isLocked());
  }
  function onPointerError(event) {
    if (isLocked()) fn?.(false);
    console.error("PointerLock error occurred:", event);
    doc.exitPointerLock();
  }
  if (!supported) return;
  try {
    body.requestPointerLock();
  } catch {
  }
  const cleanup = [
    addDomEvent(doc, "pointerlockchange", onPointerChange, false),
    addDomEvent(doc, "pointerlockerror", onPointerError, false)
  ];
  return () => {
    cleanup.forEach((cleanup2) => cleanup2());
    doc.exitPointerLock();
  };
}

// src/text-selection.ts
var state = "default";
var userSelect = "";
var elementMap = /* @__PURE__ */ new WeakMap();
function disableTextSelectionImpl(options = {}) {
  const { target, doc } = options;
  const docNode = doc ?? document;
  const rootEl = docNode.documentElement;
  if (isIos()) {
    if (state === "default") {
      userSelect = rootEl.style.webkitUserSelect;
      rootEl.style.webkitUserSelect = "none";
    }
    state = "disabled";
  } else if (target) {
    elementMap.set(target, target.style.userSelect);
    target.style.userSelect = "none";
  }
  return () => restoreTextSelection({ target, doc: docNode });
}
function restoreTextSelection(options = {}) {
  const { target, doc } = options;
  const docNode = doc ?? document;
  const rootEl = docNode.documentElement;
  if (isIos()) {
    if (state !== "disabled") return;
    state = "restoring";
    setTimeout(() => {
      nextTick(() => {
        if (state === "restoring") {
          if (rootEl.style.webkitUserSelect === "none") {
            rootEl.style.webkitUserSelect = userSelect || "";
          }
          userSelect = "";
          state = "default";
        }
      });
    }, 300);
  } else {
    if (target && elementMap.has(target)) {
      const prevUserSelect = elementMap.get(target);
      if (target.style.userSelect === "none") {
        target.style.userSelect = prevUserSelect ?? "";
      }
      if (target.getAttribute("style") === "") {
        target.removeAttribute("style");
      }
      elementMap.delete(target);
    }
  }
}
function disableTextSelection(options = {}) {
  const { defer, target, ...restOptions } = options;
  const func = defer ? raf : (v) => v();
  const cleanups = [];
  cleanups.push(
    func(() => {
      const node = typeof target === "function" ? target() : target;
      cleanups.push(disableTextSelectionImpl({ ...restOptions, target: node }));
    })
  );
  return () => {
    cleanups.forEach((fn) => fn?.());
  };
}

// src/pointer-move.ts
function trackPointerMove(doc, handlers) {
  const { onPointerMove, onPointerUp } = handlers;
  const handleMove = (event) => {
    const point = getEventPoint(event);
    const distance = Math.sqrt(point.x ** 2 + point.y ** 2);
    const moveBuffer = event.pointerType === "touch" ? 10 : 5;
    if (distance < moveBuffer) return;
    if (event.pointerType === "mouse" && event.button === 0) {
      onPointerUp();
      return;
    }
    onPointerMove({ point, event });
  };
  const cleanups = [
    addDomEvent(doc, "pointermove", handleMove, false),
    addDomEvent(doc, "pointerup", onPointerUp, false),
    addDomEvent(doc, "pointercancel", onPointerUp, false),
    addDomEvent(doc, "contextmenu", onPointerUp, false),
    disableTextSelection({ doc })
  ];
  return () => {
    cleanups.forEach((cleanup) => cleanup());
  };
}

// src/press.ts
function trackPress(options) {
  const {
    pointerNode,
    keyboardNode = pointerNode,
    onPress,
    onPressStart,
    onPressEnd,
    isValidKey = (e) => e.key === "Enter"
  } = options;
  if (!pointerNode) return noop;
  const win = getWindow(pointerNode);
  const doc = getDocument(pointerNode);
  let removeStartListeners = noop;
  let removeEndListeners = noop;
  let removeAccessibleListeners = noop;
  const getInfo = (event) => ({
    point: getEventPoint(event),
    event
  });
  function startPress(event) {
    onPressStart?.(getInfo(event));
  }
  function cancelPress(event) {
    onPressEnd?.(getInfo(event));
  }
  const startPointerPress = (startEvent) => {
    removeEndListeners();
    const endPointerPress = (endEvent) => {
      const target = getEventTarget(endEvent);
      if (contains(pointerNode, target)) {
        onPress?.(getInfo(endEvent));
      } else {
        onPressEnd?.(getInfo(endEvent));
      }
    };
    const removePointerUpListener = addDomEvent(win, "pointerup", endPointerPress, { passive: !onPress, once: true });
    const removePointerCancelListener = addDomEvent(win, "pointercancel", cancelPress, {
      passive: !onPressEnd,
      once: true
    });
    removeEndListeners = pipe(removePointerUpListener, removePointerCancelListener);
    if (doc.activeElement === keyboardNode && startEvent.pointerType === "mouse") {
      startEvent.preventDefault();
    }
    startPress(startEvent);
  };
  const removePointerListener = addDomEvent(pointerNode, "pointerdown", startPointerPress, { passive: !onPressStart });
  const removeFocusListener = addDomEvent(keyboardNode, "focus", startAccessiblePress);
  removeStartListeners = pipe(removePointerListener, removeFocusListener);
  function startAccessiblePress() {
    const handleKeydown = (keydownEvent) => {
      if (!isValidKey(keydownEvent)) return;
      const handleKeyup = (keyupEvent) => {
        if (!isValidKey(keyupEvent)) return;
        const evt2 = new win.PointerEvent("pointerup");
        const info = getInfo(evt2);
        onPress?.(info);
        onPressEnd?.(info);
      };
      removeEndListeners();
      removeEndListeners = addDomEvent(keyboardNode, "keyup", handleKeyup);
      const evt = new win.PointerEvent("pointerdown");
      startPress(evt);
    };
    const handleBlur = () => {
      const evt = new win.PointerEvent("pointercancel");
      cancelPress(evt);
    };
    const removeKeydownListener = addDomEvent(keyboardNode, "keydown", handleKeydown);
    const removeBlurListener = addDomEvent(keyboardNode, "blur", handleBlur);
    removeAccessibleListeners = pipe(removeKeydownListener, removeBlurListener);
  }
  return () => {
    removeStartListeners();
    removeEndListeners();
    removeAccessibleListeners();
  };
}

// src/proxy-tab-focus.ts
function proxyTabFocusImpl(container, options = {}) {
  const { triggerElement, onFocus, onFocusEnter } = options;
  const doc = container?.ownerDocument || document;
  const body = doc.body;
  function onKeyDown(event) {
    if (event.key !== "Tab") return;
    let elementToFocus = null;
    const [firstTabbable, lastTabbable] = getTabbableEdges(container, true);
    const nextTabbableAfterTrigger = getNextTabbable(body, triggerElement);
    const noTabbableElements = !firstTabbable && !lastTabbable;
    if (event.shiftKey && nextTabbableAfterTrigger === doc.activeElement) {
      onFocusEnter?.();
      elementToFocus = lastTabbable;
    } else if (event.shiftKey && (doc.activeElement === firstTabbable || noTabbableElements)) {
      elementToFocus = triggerElement;
    } else if (!event.shiftKey && doc.activeElement === triggerElement) {
      onFocusEnter?.();
      elementToFocus = firstTabbable;
    } else if (!event.shiftKey && (doc.activeElement === lastTabbable || noTabbableElements)) {
      elementToFocus = nextTabbableAfterTrigger;
    }
    if (!elementToFocus) return;
    event.preventDefault();
    if (typeof onFocus === "function") {
      onFocus(elementToFocus);
    } else {
      elementToFocus.focus();
    }
  }
  return addDomEvent(doc, "keydown", onKeyDown, true);
}
function proxyTabFocus(container, options) {
  const { defer, triggerElement, ...restOptions } = options;
  const func = defer ? raf : (v) => v();
  const cleanups = [];
  cleanups.push(
    func(() => {
      const node = typeof container === "function" ? container() : container;
      const trigger = typeof triggerElement === "function" ? triggerElement() : triggerElement;
      cleanups.push(proxyTabFocusImpl(node, { triggerElement: trigger, ...restOptions }));
    })
  );
  return () => {
    cleanups.forEach((fn) => fn?.());
  };
}

// src/query.ts
function queryAll(root, selector) {
  return Array.from(root?.querySelectorAll(selector) ?? []);
}
function query(root, selector) {
  return root?.querySelector(selector) ?? null;
}
var defaultItemToId = (v) => v.id;
function itemById(v, id, itemToId = defaultItemToId) {
  return v.find((item) => itemToId(item) === id);
}
function indexOfId(v, id, itemToId = defaultItemToId) {
  const item = itemById(v, id, itemToId);
  return item ? v.indexOf(item) : -1;
}
function nextById(v, id, loop = true) {
  let idx = indexOfId(v, id);
  idx = loop ? (idx + 1) % v.length : Math.min(idx + 1, v.length - 1);
  return v[idx];
}
function prevById(v, id, loop = true) {
  let idx = indexOfId(v, id);
  if (idx === -1) return loop ? v[v.length - 1] : null;
  idx = loop ? (idx - 1 + v.length) % v.length : Math.max(0, idx - 1);
  return v[idx];
}

// src/resize-observer.ts
function trackElementRect(elements, options) {
  const { onEntry, measure, box = "border-box" } = options;
  const elems = (Array.isArray(elements) ? elements : [elements]).filter(isHTMLElement);
  const win = getWindow(elems[0]);
  const trigger = (entries) => {
    const rects = elems.map((el) => measure(el));
    onEntry({ rects, entries });
  };
  trigger([]);
  const obs = new win.ResizeObserver(trigger);
  elems.forEach((el) => obs.observe(el, { box }));
  return () => obs.disconnect();
}

// src/scope.ts
function createScope(methods) {
  const dom = {
    getRootNode: (ctx) => ctx.getRootNode?.() ?? document,
    getDoc: (ctx) => getDocument(dom.getRootNode(ctx)),
    getWin: (ctx) => dom.getDoc(ctx).defaultView ?? window,
    getActiveElement: (ctx) => getActiveElement(dom.getRootNode(ctx)),
    isActiveElement: (ctx, elem) => elem === dom.getActiveElement(ctx),
    getById: (ctx, id) => dom.getRootNode(ctx).getElementById(id),
    setValue: (elem, value) => {
      if (elem == null || value == null) return;
      setElementValue(elem, value.toString());
    }
  };
  return { ...dom, ...methods };
}

// src/searchable.ts
var sanitize = (str) => str.split("").map((char) => {
  const code = char.charCodeAt(0);
  if (code > 0 && code < 128) return char;
  if (code >= 128 && code <= 255) return `/x${code.toString(16)}`.replace("/", "\\");
  return "";
}).join("").trim();
var getValueText = (el) => {
  return sanitize(el.dataset?.valuetext ?? el.textContent ?? "");
};
var match = (valueText, query2) => {
  return valueText.trim().toLowerCase().startsWith(query2.toLowerCase());
};
function getByText(v, text, currentId, itemToId = defaultItemToId) {
  const index = currentId ? indexOfId(v, currentId, itemToId) : -1;
  let items = currentId ? wrap(v, index) : v;
  const isSingleKey = text.length === 1;
  if (isSingleKey) {
    items = items.filter((item) => itemToId(item) !== currentId);
  }
  return items.find((item) => match(getValueText(item), text));
}

// src/set.ts
function setAttribute(el, attr, v) {
  const prev = el.getAttribute(attr);
  const exists = prev != null;
  el.setAttribute(attr, v);
  return () => {
    if (!exists) {
      el.removeAttribute(attr);
    } else {
      el.setAttribute(attr, prev);
    }
  };
}
function setProperty(el, prop, v) {
  const exists = prop in el;
  const prev = el[prop];
  el[prop] = v;
  return () => {
    if (!exists) {
      delete el[prop];
    } else {
      el[prop] = prev;
    }
  };
}
function setStyle(el, style) {
  if (!el) return noop;
  const prev = Object.keys(style).reduce((acc, key) => {
    acc[key] = el.style.getPropertyValue(key);
    return acc;
  }, {});
  Object.assign(el.style, style);
  return () => {
    Object.assign(el.style, prev);
    if (el.style.length === 0) {
      el.removeAttribute("style");
    }
  };
}
function setStyleProperty(el, prop, value) {
  if (!el) return noop;
  const prev = el.style.getPropertyValue(prop);
  el.style.setProperty(prop, value);
  return () => {
    el.style.setProperty(prop, prev);
    if (el.style.length === 0) {
      el.removeAttribute("style");
    }
  };
}

// src/typeahead.ts
function getByTypeaheadImpl(baseItems, options) {
  const { state: state2, activeId, key, timeout = 350, itemToId } = options;
  const search = state2.keysSoFar + key;
  const isRepeated = search.length > 1 && Array.from(search).every((char) => char === search[0]);
  const query2 = isRepeated ? search[0] : search;
  let items = baseItems.slice();
  const next = getByText(items, query2, activeId, itemToId);
  function cleanup() {
    clearTimeout(state2.timer);
    state2.timer = -1;
  }
  function update(value) {
    state2.keysSoFar = value;
    cleanup();
    if (value !== "") {
      state2.timer = +setTimeout(() => {
        update("");
        cleanup();
      }, timeout);
    }
  }
  update(search);
  return next;
}
var getByTypeahead = /* @__PURE__ */ Object.assign(getByTypeaheadImpl, {
  defaultOptions: { keysSoFar: "", timer: -1 },
  isValidEvent: isValidTypeaheadEvent
});
function isValidTypeaheadEvent(event) {
  return event.key.length === 1 && !event.ctrlKey && !event.metaKey;
}

// src/visual-viewport.ts
function trackVisualViewport(doc, fn) {
  const win = doc?.defaultView || window;
  const onResize = () => {
    fn?.(getViewportSize(win));
  };
  onResize();
  return addDomEvent(win.visualViewport ?? win, "resize", onResize);
}
function getViewportSize(win) {
  return {
    width: win.visualViewport?.width || win.innerWidth,
    height: win.visualViewport?.height || win.innerHeight
  };
}

// src/visually-hidden.ts
var visuallyHiddenStyle = {
  border: "0",
  clip: "rect(0 0 0 0)",
  height: "1px",
  margin: "-1px",
  overflow: "hidden",
  padding: "0",
  position: "absolute",
  width: "1px",
  whiteSpace: "nowrap",
  wordWrap: "normal"
};
function setVisuallyHidden(el) {
  Object.assign(el.style, visuallyHiddenStyle);
}

// src/wait-for.ts
var fps = 1e3 / 60;
function waitForElement(query2, cb) {
  const el = query2();
  if (isHTMLElement(el) && el.isConnected) {
    cb(el);
    return () => void 0;
  } else {
    const timerId = setInterval(() => {
      const el2 = query2();
      if (isHTMLElement(el2) && el2.isConnected) {
        cb(el2);
        clearInterval(timerId);
      }
    }, fps);
    return () => clearInterval(timerId);
  }
}
function waitForElements(queries, cb) {
  const cleanups = [];
  queries?.forEach((query2) => {
    const clean = waitForElement(query2, cb);
    cleanups.push(clean);
  });
  return () => {
    cleanups.forEach((fn) => fn());
  };
}

exports.MAX_Z_INDEX = MAX_Z_INDEX;
exports.addDomEvent = addDomEvent;
exports.ariaAttr = ariaAttr;
exports.clickIfLink = clickIfLink;
exports.contains = contains;
exports.createScope = createScope;
exports.dataAttr = dataAttr;
exports.defaultItemToId = defaultItemToId;
exports.disableTextSelection = disableTextSelection;
exports.dispatchInputCheckedEvent = dispatchInputCheckedEvent;
exports.dispatchInputValueEvent = dispatchInputValueEvent;
exports.getActiveElement = getActiveElement;
exports.getBeforeInputValue = getBeforeInputValue;
exports.getByText = getByText;
exports.getByTypeahead = getByTypeahead;
exports.getComputedStyle = getComputedStyle;
exports.getDataUrl = getDataUrl;
exports.getDocument = getDocument;
exports.getDocumentElement = getDocumentElement;
exports.getEventKey = getEventKey;
exports.getEventPoint = getEventPoint;
exports.getEventStep = getEventStep;
exports.getEventTarget = getEventTarget;
exports.getFirstFocusable = getFirstFocusable;
exports.getFirstTabbable = getFirstTabbable;
exports.getFocusables = getFocusables;
exports.getInitialFocus = getInitialFocus;
exports.getLastTabbable = getLastTabbable;
exports.getNativeEvent = getNativeEvent;
exports.getNearestOverflowAncestor = getNearestOverflowAncestor;
exports.getNextTabbable = getNextTabbable;
exports.getNodeName = getNodeName;
exports.getOverflowAncestors = getOverflowAncestors;
exports.getParentNode = getParentNode;
exports.getPlatform = getPlatform;
exports.getRelativePoint = getRelativePoint;
exports.getScrollPosition = getScrollPosition;
exports.getTabIndex = getTabIndex;
exports.getTabbableEdges = getTabbableEdges;
exports.getTabbables = getTabbables;
exports.getUserAgent = getUserAgent;
exports.getWindow = getWindow;
exports.indexOfId = indexOfId;
exports.isAnchorElement = isAnchorElement;
exports.isAndroid = isAndroid;
exports.isApple = isApple;
exports.isCaretAtStart = isCaretAtStart;
exports.isChrome = isChrome;
exports.isComposingEvent = isComposingEvent;
exports.isContextMenuEvent = isContextMenuEvent;
exports.isCtrlOrMetaKey = isCtrlOrMetaKey;
exports.isDocument = isDocument;
exports.isDom = isDom;
exports.isDownloadingEvent = isDownloadingEvent;
exports.isEditableElement = isEditableElement;
exports.isElementVisible = isElementVisible;
exports.isFirefox = isFirefox;
exports.isFocusable = isFocusable;
exports.isHTMLElement = isHTMLElement;
exports.isIPad = isIPad;
exports.isIPhone = isIPhone;
exports.isInView = isInView;
exports.isInputElement = isInputElement;
exports.isIos = isIos;
exports.isKeyboardClick = isKeyboardClick;
exports.isLeftClick = isLeftClick;
exports.isMac = isMac;
exports.isModifierKey = isModifierKey;
exports.isNode = isNode;
exports.isOpeningInNewTab = isOpeningInNewTab;
exports.isOverflowElement = isOverflowElement;
exports.isPrintableKey = isPrintableKey;
exports.isRootElement = isRootElement;
exports.isSafari = isSafari;
exports.isSelfTarget = isSelfTarget;
exports.isShadowRoot = isShadowRoot;
exports.isTabbable = isTabbable;
exports.isTouchDevice = isTouchDevice;
exports.isTouchEvent = isTouchEvent;
exports.isValidTabEvent = isValidTabEvent;
exports.isVirtualClick = isVirtualClick;
exports.isVirtualPointerEvent = isVirtualPointerEvent;
exports.isVisualViewport = isVisualViewport;
exports.isWebKit = isWebKit;
exports.isWindow = isWindow;
exports.itemById = itemById;
exports.nextById = nextById;
exports.nextTick = nextTick;
exports.observeAttributes = observeAttributes;
exports.observeChildren = observeChildren;
exports.prevById = prevById;
exports.proxyTabFocus = proxyTabFocus;
exports.query = query;
exports.queryAll = queryAll;
exports.queueBeforeEvent = queueBeforeEvent;
exports.raf = raf;
exports.requestPointerLock = requestPointerLock;
exports.restoreTextSelection = restoreTextSelection;
exports.scrollIntoView = scrollIntoView;
exports.setAttribute = setAttribute;
exports.setCaretToEnd = setCaretToEnd;
exports.setElementChecked = setElementChecked;
exports.setElementValue = setElementValue;
exports.setProperty = setProperty;
exports.setStyle = setStyle;
exports.setStyleProperty = setStyleProperty;
exports.setVisuallyHidden = setVisuallyHidden;
exports.trackElementRect = trackElementRect;
exports.trackFormControl = trackFormControl;
exports.trackPointerMove = trackPointerMove;
exports.trackPress = trackPress;
exports.trackVisualViewport = trackVisualViewport;
exports.visuallyHiddenStyle = visuallyHiddenStyle;
exports.waitForElement = waitForElement;
exports.waitForElements = waitForElements;
