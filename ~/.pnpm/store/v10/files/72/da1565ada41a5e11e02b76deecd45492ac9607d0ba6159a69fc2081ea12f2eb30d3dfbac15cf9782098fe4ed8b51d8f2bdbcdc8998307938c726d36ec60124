'use strict';

const unhead = require('unhead');
const vue = require('vue');
const shared = require('@unhead/shared');

const Vue3 = vue.version[0] === "3";

function resolveUnref(r) {
  return typeof r === "function" ? r() : vue.unref(r);
}
function resolveUnrefHeadInput(ref) {
  if (ref instanceof Promise || ref instanceof Date || ref instanceof RegExp)
    return ref;
  const root = resolveUnref(ref);
  if (!ref || !root)
    return root;
  if (Array.isArray(root))
    return root.map((r) => resolveUnrefHeadInput(r));
  if (typeof root === "object") {
    const resolved = {};
    for (const k in root) {
      if (!Object.prototype.hasOwnProperty.call(root, k)) {
        continue;
      }
      if (k === "titleTemplate" || k[0] === "o" && k[1] === "n") {
        resolved[k] = vue.unref(root[k]);
        continue;
      }
      resolved[k] = resolveUnrefHeadInput(root[k]);
    }
    return resolved;
  }
  return root;
}

const VueReactivityPlugin = shared.defineHeadPlugin({
  hooks: {
    "entries:resolve": (ctx) => {
      for (const entry of ctx.entries)
        entry.resolvedInput = resolveUnrefHeadInput(entry.input);
    }
  }
});

const headSymbol = "usehead";
function vueInstall(head) {
  const plugin = {
    install(app) {
      if (Vue3) {
        app.config.globalProperties.$unhead = head;
        app.config.globalProperties.$head = head;
        app.provide(headSymbol, head);
      }
    }
  };
  return plugin.install;
}
function createServerHead(options = {}) {
  const head = unhead.createServerHead(options);
  head.use(VueReactivityPlugin);
  head.install = vueInstall(head);
  return head;
}
function createHead(options = {}) {
  options.domDelayFn = options.domDelayFn || ((fn) => vue.nextTick(() => setTimeout(() => fn(), 0)));
  const head = unhead.createHead(options);
  head.use(VueReactivityPlugin);
  head.install = vueInstall(head);
  return head;
}

const _global = typeof globalThis !== "undefined" ? globalThis : typeof window !== "undefined" ? window : typeof global !== "undefined" ? global : typeof self !== "undefined" ? self : {};
const globalKey = "__unhead_injection_handler__";
function setHeadInjectionHandler(handler) {
  _global[globalKey] = handler;
}
function injectHead() {
  if (globalKey in _global) {
    return _global[globalKey]();
  }
  const head = vue.inject(headSymbol);
  if (!head && process.env.NODE_ENV !== "production")
    console.warn("Unhead is missing Vue context, falling back to shared context. This may have unexpected results.");
  return head || unhead.getActiveHead();
}

exports.Vue3 = Vue3;
exports.createHead = createHead;
exports.createServerHead = createServerHead;
exports.headSymbol = headSymbol;
exports.injectHead = injectHead;
exports.resolveUnrefHeadInput = resolveUnrefHeadInput;
exports.setHeadInjectionHandler = setHeadInjectionHandler;
