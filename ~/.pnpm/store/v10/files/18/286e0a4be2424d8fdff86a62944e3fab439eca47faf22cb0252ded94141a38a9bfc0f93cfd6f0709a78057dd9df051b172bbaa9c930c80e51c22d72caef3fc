'use strict';

var domQuery = require('@zag-js/dom-query');

// src/autoresize-input.ts
function getVisualStyles(node) {
  if (!node) return;
  const style = domQuery.getComputedStyle(node);
  return "box-sizing:" + style.boxSizing + ";border-left:" + style.borderLeftWidth + " solid red;border-right:" + style.borderRightWidth + " solid red;font-family:" + style.fontFamily + ";font-feature-settings:" + style.fontFeatureSettings + ";font-kerning:" + style.fontKerning + ";font-size:" + style.fontSize + ";font-stretch:" + style.fontStretch + ";font-style:" + style.fontStyle + ";font-variant:" + style.fontVariant + ";font-variant-caps:" + style.fontVariantCaps + ";font-variant-ligatures:" + style.fontVariantLigatures + ";font-variant-numeric:" + style.fontVariantNumeric + ";font-weight:" + style.fontWeight + ";letter-spacing:" + style.letterSpacing + ";margin-left:" + style.marginLeft + ";margin-right:" + style.marginRight + ";padding-left:" + style.paddingLeft + ";padding-right:" + style.paddingRight + ";text-indent:" + style.textIndent + ";text-transform:" + style.textTransform;
}

// src/autoresize-input.ts
function createGhostElement(doc) {
  var el = doc.createElement("div");
  el.id = "ghost";
  el.style.cssText = "display:inline-block;height:0;overflow:hidden;position:absolute;top:0;visibility:hidden;white-space:nowrap;";
  doc.body.appendChild(el);
  return el;
}
function autoResizeInput(input) {
  if (!input) return;
  const doc = domQuery.getDocument(input);
  const win = domQuery.getWindow(input);
  const ghost = createGhostElement(doc);
  const cssText = getVisualStyles(input);
  if (cssText) ghost.style.cssText += cssText;
  function resize() {
    win.requestAnimationFrame(() => {
      ghost.innerHTML = input.value;
      const rect = win.getComputedStyle(ghost);
      input?.style.setProperty("width", rect.width);
    });
  }
  resize();
  input?.addEventListener("input", resize);
  input?.addEventListener("change", resize);
  return () => {
    doc.body.removeChild(ghost);
    input?.removeEventListener("input", resize);
    input?.removeEventListener("change", resize);
  };
}
var autoresizeTextarea = (el) => {
  if (!el) return;
  const style = domQuery.getComputedStyle(el);
  const win = domQuery.getWindow(el);
  const doc = domQuery.getDocument(el);
  const resize = () => {
    requestAnimationFrame(() => {
      el.style.height = "auto";
      let newHeight;
      if (style.boxSizing === "content-box") {
        newHeight = el.scrollHeight - (parseFloat(style.paddingTop) + parseFloat(style.paddingBottom));
      } else {
        newHeight = el.scrollHeight + parseFloat(style.borderTopWidth) + parseFloat(style.borderBottomWidth);
      }
      if (style.maxHeight !== "none" && newHeight > parseFloat(style.maxHeight)) {
        if (style.overflowY === "hidden") {
          el.style.overflowY = "scroll";
        }
        newHeight = parseFloat(style.maxHeight);
      } else if (style.overflowY !== "hidden") {
        el.style.overflowY = "hidden";
      }
      el.style.height = `${newHeight}px`;
    });
  };
  el.addEventListener("input", resize);
  el.form?.addEventListener("reset", resize);
  const elementPrototype = Object.getPrototypeOf(el);
  const descriptor = Object.getOwnPropertyDescriptor(elementPrototype, "value");
  Object.defineProperty(el, "value", {
    ...descriptor,
    set() {
      descriptor?.set?.apply(this, arguments);
      resize();
    }
  });
  const resizeObserver = new win.ResizeObserver(() => {
    requestAnimationFrame(() => resize());
  });
  resizeObserver.observe(el);
  const attrObserver = new win.MutationObserver(() => resize());
  attrObserver.observe(el, { attributes: true, attributeFilter: ["rows", "placeholder"] });
  doc.fonts?.addEventListener("loadingdone", resize);
  return () => {
    el.removeEventListener("input", resize);
    el.form?.removeEventListener("reset", resize);
    doc.fonts?.removeEventListener("loadingdone", resize);
    resizeObserver.disconnect();
    attrObserver.disconnect();
  };
};

exports.autoResizeInput = autoResizeInput;
exports.autoresizeTextarea = autoresizeTextarea;
