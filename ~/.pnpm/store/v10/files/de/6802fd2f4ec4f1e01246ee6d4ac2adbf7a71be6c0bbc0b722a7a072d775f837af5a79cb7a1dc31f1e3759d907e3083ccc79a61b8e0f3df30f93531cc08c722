var _VueDemiGlobal = typeof globalThis !== 'undefined' 
  ? globalThis
  : typeof global !== 'undefined'
    ? global
    : typeof self !== 'undefined'
      ? self
      : this
var VueDemi = (function (VueDemi, Vue, VueCompositionAPI) {
  if (VueDemi.install) {
    return VueDemi
  }
  if (!Vue) {
    console.error('[vue-demi] no Vue instance found, please be sure to import `vue` before `vue-demi`.')
    return VueDemi
  }

  // Vue 2.7
  if (Vue.version.slice(0, 4) === '2.7.') {
    for (var key in Vue) {
      VueDemi[key] = Vue[key]
    }
    VueDemi.isVue2 = true
    VueDemi.isVue3 = false
    VueDemi.install = function () {}
    VueDemi.Vue = Vue
    VueDemi.Vue2 = Vue
    VueDemi.version = Vue.version
    VueDemi.warn = Vue.util.warn
    VueDemi.hasInjectionContext = function() {
      return !!VueDemi.getCurrentInstance()
    }
    function createApp(rootComponent, rootProps) {
      var vm
      var provide = {}
      var app = {
        config: Vue.config,
        use: Vue.use.bind(Vue),
        mixin: Vue.mixin.bind(Vue),
        component: Vue.component.bind(Vue),
        provide: function (key, value) {
          provide[key] = value
          return this
        },
        directive: function (name, dir) {
          if (dir) {
            Vue.directive(name, dir)
            return app
          } else {
            return Vue.directive(name)
          }
        },
        mount: function (el, hydrating) {
          if (!vm) {
            vm = new Vue(Object.assign({ propsData: rootProps }, rootComponent, { provide: Object.assign(provide, rootComponent.provide) }))
            vm.$mount(el, hydrating)
            return vm
          } else {
            return vm
          }
        },
        unmount: function () {
          if (vm) {
            vm.$destroy()
            vm = undefined
          }
        },
      }
      return app
    }
    VueDemi.createApp = createApp
  }
  // Vue 2.6.x
  else if (Vue.version.slice(0, 2) === '2.') {
    if (VueCompositionAPI) {
      for (var key in VueCompositionAPI) {
        VueDemi[key] = VueCompositionAPI[key]
      }
      VueDemi.isVue2 = true
      VueDemi.isVue3 = false
      VueDemi.install = function () {}
      VueDemi.Vue = Vue
      VueDemi.Vue2 = Vue
      VueDemi.version = Vue.version
      VueDemi.hasInjectionContext = function() {
        return !!VueDemi.getCurrentInstance()
      }
    } else {
      console.error('[vue-demi] no VueCompositionAPI instance found, please be sure to import `@vue/composition-api` before `vue-demi`.')
    }
  }
  // Vue 3
  else if (Vue.version.slice(0, 2) === '3.') {
    for (var key in Vue) {
      VueDemi[key] = Vue[key]
    }
    VueDemi.isVue2 = false
    VueDemi.isVue3 = true
    VueDemi.install = function () {}
    VueDemi.Vue = Vue
    VueDemi.Vue2 = undefined
    VueDemi.version = Vue.version
    VueDemi.set = function (target, key, val) {
      if (Array.isArray(target)) {
        target.length = Math.max(target.length, key)
        target.splice(key, 1, val)
        return val
      }
      target[key] = val
      return val
    }
    VueDemi.del = function (target, key) {
      if (Array.isArray(target)) {
        target.splice(key, 1)
        return
      }
      delete target[key]
    }
  } else {
    console.error('[vue-demi] Vue version ' + Vue.version + ' is unsupported.')
  }
  return VueDemi
})(
  (_VueDemiGlobal.VueDemi = _VueDemiGlobal.VueDemi || (typeof VueDemi !== 'undefined' ? VueDemi : {})),
  _VueDemiGlobal.Vue || (typeof Vue !== 'undefined' ? Vue : undefined),
  _VueDemiGlobal.VueCompositionAPI || (typeof VueCompositionAPI !== 'undefined' ? VueCompositionAPI : undefined)
);
;
;(function (exports, shared, axios, vueDemi) {
  'use strict';

  function useAxios(...args) {
    const url = typeof args[0] === "string" ? args[0] : void 0;
    const argsPlaceholder = typeof url === "string" ? 1 : 0;
    const defaultOptions = {
      immediate: !!argsPlaceholder,
      shallow: true,
      abortPrevious: true
    };
    let defaultConfig = {};
    let instance = axios;
    let options = defaultOptions;
    const isAxiosInstance = (val) => !!(val == null ? void 0 : val.request);
    if (args.length > 0 + argsPlaceholder) {
      if (isAxiosInstance(args[0 + argsPlaceholder]))
        instance = args[0 + argsPlaceholder];
      else
        defaultConfig = args[0 + argsPlaceholder];
    }
    if (args.length > 1 + argsPlaceholder) {
      if (isAxiosInstance(args[1 + argsPlaceholder]))
        instance = args[1 + argsPlaceholder];
    }
    if (args.length === 2 + argsPlaceholder && !isAxiosInstance(args[1 + argsPlaceholder]) || args.length === 3 + argsPlaceholder) {
      options = args[args.length - 1] || defaultOptions;
    }
    const {
      initialData,
      shallow,
      onSuccess = shared.noop,
      onError = shared.noop,
      immediate,
      resetOnExecute = false
    } = options;
    const response = vueDemi.shallowRef();
    const data = (shallow ? vueDemi.shallowRef : vueDemi.ref)(initialData);
    const isFinished = vueDemi.ref(false);
    const isLoading = vueDemi.ref(false);
    const isAborted = vueDemi.ref(false);
    const error = vueDemi.shallowRef();
    let abortController = new AbortController();
    const abort = (message) => {
      if (isFinished.value || !isLoading.value)
        return;
      abortController.abort(message);
      abortController = new AbortController();
      isAborted.value = true;
      isLoading.value = false;
      isFinished.value = false;
    };
    const loading = (loading2) => {
      isLoading.value = loading2;
      isFinished.value = !loading2;
    };
    const resetData = () => {
      if (resetOnExecute)
        data.value = initialData;
    };
    const waitUntilFinished = () => new Promise((resolve, reject) => {
      shared.until(isFinished).toBe(true).then(() => error.value ? reject(error.value) : resolve(result));
    });
    const promise = {
      then: (...args2) => waitUntilFinished().then(...args2),
      catch: (...args2) => waitUntilFinished().catch(...args2)
    };
    let executeCounter = 0;
    const execute = (executeUrl = url, config = {}) => {
      error.value = void 0;
      const _url = typeof executeUrl === "string" ? executeUrl : url != null ? url : config.url;
      if (_url === void 0) {
        error.value = new axios.AxiosError(axios.AxiosError.ERR_INVALID_URL);
        isFinished.value = true;
        return promise;
      }
      resetData();
      if (options.abortPrevious !== false)
        abort();
      loading(true);
      executeCounter += 1;
      const currentExecuteCounter = executeCounter;
      isAborted.value = false;
      instance(_url, { ...defaultConfig, ...typeof executeUrl === "object" ? executeUrl : config, signal: abortController.signal }).then((r) => {
        if (isAborted.value)
          return;
        response.value = r;
        const result2 = r.data;
        data.value = result2;
        onSuccess(result2);
      }).catch((e) => {
        error.value = e;
        onError(e);
      }).finally(() => {
        var _a;
        (_a = options.onFinish) == null ? void 0 : _a.call(options);
        if (currentExecuteCounter === executeCounter)
          loading(false);
      });
      return promise;
    };
    if (immediate && url)
      execute();
    const result = {
      response,
      data,
      error,
      isFinished,
      isLoading,
      cancel: abort,
      isAborted,
      isCanceled: isAborted,
      abort,
      execute
    };
    return {
      ...result,
      ...promise
    };
  }

  exports.useAxios = useAxios;

})(this.VueUse = this.VueUse || {}, VueUse, axios, VueDemi);
