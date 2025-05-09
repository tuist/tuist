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
;(function (exports, shared, Cookie, vueDemi) {
  'use strict';

  function createCookies(req) {
    const universalCookie = new Cookie(req ? req.headers.cookie : null);
    return (dependencies, { doNotParse = false, autoUpdateDependencies = false } = {}) => useCookies(dependencies, { doNotParse, autoUpdateDependencies }, universalCookie);
  }
  function useCookies(dependencies, { doNotParse = false, autoUpdateDependencies = false } = {}, cookies = new Cookie()) {
    const watchingDependencies = autoUpdateDependencies ? [...dependencies || []] : dependencies;
    let previousCookies = cookies.getAll({ doNotParse: true });
    const touches = vueDemi.ref(0);
    const onChange = () => {
      const newCookies = cookies.getAll({ doNotParse: true });
      if (shouldUpdate(
        watchingDependencies || null,
        newCookies,
        previousCookies
      )) {
        touches.value++;
      }
      previousCookies = newCookies;
    };
    cookies.addChangeListener(onChange);
    shared.tryOnScopeDispose(() => {
      cookies.removeChangeListener(onChange);
    });
    return {
      /**
       * Reactive get cookie by name. If **autoUpdateDependencies = true** then it will update watching dependencies
       */
      get: (...args) => {
        if (autoUpdateDependencies && watchingDependencies && !watchingDependencies.includes(args[0]))
          watchingDependencies.push(args[0]);
        touches.value;
        return cookies.get(args[0], { doNotParse, ...args[1] });
      },
      /**
       * Reactive get all cookies
       */
      getAll: (...args) => {
        touches.value;
        return cookies.getAll({ doNotParse, ...args[0] });
      },
      set: (...args) => cookies.set(...args),
      remove: (...args) => cookies.remove(...args),
      addChangeListener: (...args) => cookies.addChangeListener(...args),
      removeChangeListener: (...args) => cookies.removeChangeListener(...args)
    };
  }
  function shouldUpdate(dependencies, newCookies, oldCookies) {
    if (!dependencies)
      return true;
    for (const dependency of dependencies) {
      if (newCookies[dependency] !== oldCookies[dependency])
        return true;
    }
    return false;
  }

  exports.createCookies = createCookies;
  exports.useCookies = useCookies;

})(this.VueUse = this.VueUse || {}, VueUse, UniversalCookie, VueDemi);
