'use strict';

const unhead = require('unhead');
const injectHead = require('./shared/vue.DWlmwWrc.cjs');
const shared = require('@unhead/shared');
const useHead = require('./shared/vue.BmMjB48i.cjs');
const vue = require('vue');

const coreComposableNames = [
  "injectHead"
];
const unheadVueComposablesImports = {
  "@unhead/vue": [...coreComposableNames, ...shared.composableNames]
};

function useHeadSafe(input, options = {}) {
  return useHead.useHead(input, { ...options, transform: shared.whitelistSafeInput });
}

function registerVueScopeHandlers(script, scope) {
  if (!scope) {
    return;
  }
  const _registerCb = (key, cb) => {
    if (!script._cbs[key]) {
      cb(script.instance);
      return () => {
      };
    }
    let i = script._cbs[key].push(cb);
    const destroy = () => {
      if (i) {
        script._cbs[key]?.splice(i - 1, 1);
        i = null;
      }
    };
    vue.onScopeDispose(destroy);
    return destroy;
  };
  script.onLoaded = (cb) => _registerCb("loaded", cb);
  script.onError = (cb) => _registerCb("error", cb);
  vue.onScopeDispose(() => {
    script._triggerAbortController?.abort();
  });
}
function useScript(_input, _options) {
  const input = typeof _input === "string" ? { src: _input } : _input;
  const options = _options || {};
  const head = options?.head || injectHead.injectHead();
  options.head = head;
  const scope = vue.getCurrentInstance();
  options.eventContext = scope;
  if (scope && typeof options.trigger === "undefined") {
    options.trigger = vue.onMounted;
  } else if (vue.isRef(options.trigger)) {
    const refTrigger = options.trigger;
    let off;
    options.trigger = new Promise((resolve) => {
      off = vue.watch(refTrigger, (val) => {
        if (val) {
          resolve(true);
        }
      }, {
        immediate: true
      });
      vue.onScopeDispose(() => resolve(false), true);
    }).then((val) => {
      off?.();
      return val;
    });
  }
  head._scriptStatusWatcher = head._scriptStatusWatcher || head.hooks.hook("script:updated", ({ script: s }) => {
    s._statusRef.value = s.status;
  });
  const script = unhead.useScript(input, options);
  script._statusRef = script._statusRef || vue.ref(script.status);
  registerVueScopeHandlers(script, scope);
  return new Proxy(script, {
    get(_, key, a) {
      return Reflect.get(_, key === "status" ? "_statusRef" : key, a);
    }
  });
}

function useSeoMeta(input, options) {
  const { title, titleTemplate, ...meta } = input;
  return useHead.useHead({
    title,
    titleTemplate,
    // @ts-expect-error runtime type
    _flatMeta: meta
  }, {
    ...options,
    transform(t) {
      const meta2 = shared.unpackMeta({ ...t._flatMeta });
      delete t._flatMeta;
      return {
        // @ts-expect-error runtime type
        ...t,
        meta: meta2
      };
    }
  });
}

function useServerHead(input, options = {}) {
  const head = options.head || injectHead.injectHead();
  delete options.head;
  if (head)
    return head.push(input, { ...options, mode: "server" });
}

function useServerHeadSafe(input, options = {}) {
  return useHeadSafe(input, { ...options, mode: "server" });
}

function useServerSeoMeta(input, options) {
  return useSeoMeta(input, { ...options, mode: "server" });
}

const Vue2ProvideUnheadPlugin = (_Vue, head) => {
  _Vue.mixin({
    beforeCreate() {
      const options = this.$options;
      const origProvide = options.provide;
      options.provide = function() {
        let origProvideResult;
        if (typeof origProvide === "function")
          origProvideResult = origProvide.call(this);
        else
          origProvideResult = origProvide || {};
        return {
          ...origProvideResult,
          [injectHead.headSymbol]: head
        };
      };
    }
  });
};

const VueHeadMixin = {
  created() {
    let source = false;
    if (injectHead.Vue3) {
      const instance = vue.getCurrentInstance();
      if (!instance)
        return;
      const options = instance.type;
      if (!options || !("head" in options))
        return;
      source = typeof options.head === "function" ? () => options.head.call(instance.proxy) : options.head;
    } else {
      const head = this.$options.head;
      if (head) {
        source = typeof head === "function" ? () => head.call(this) : head;
      }
    }
    source && useHead.useHead(source);
  }
};

exports.CapoPlugin = unhead.CapoPlugin;
exports.HashHydrationPlugin = unhead.HashHydrationPlugin;
exports.createHeadCore = unhead.createHeadCore;
exports.createHead = injectHead.createHead;
exports.createServerHead = injectHead.createServerHead;
exports.injectHead = injectHead.injectHead;
exports.resolveUnrefHeadInput = injectHead.resolveUnrefHeadInput;
exports.setHeadInjectionHandler = injectHead.setHeadInjectionHandler;
exports.useHead = useHead.useHead;
exports.Vue2ProvideUnheadPlugin = Vue2ProvideUnheadPlugin;
exports.VueHeadMixin = VueHeadMixin;
exports.unheadVueComposablesImports = unheadVueComposablesImports;
exports.useHeadSafe = useHeadSafe;
exports.useScript = useScript;
exports.useSeoMeta = useSeoMeta;
exports.useServerHead = useServerHead;
exports.useServerHeadSafe = useServerHeadSafe;
exports.useServerSeoMeta = useServerSeoMeta;
