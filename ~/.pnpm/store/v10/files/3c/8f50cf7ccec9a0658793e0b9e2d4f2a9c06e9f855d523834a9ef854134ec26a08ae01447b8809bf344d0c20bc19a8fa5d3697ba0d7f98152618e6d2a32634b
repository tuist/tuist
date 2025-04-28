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
;(function (exports, core, shared, drauu, vueDemi) {
  'use strict';

  function useDrauu(target, options) {
    const drauuInstance = vueDemi.ref();
    let disposables = [];
    const onChangedHook = core.createEventHook();
    const onCanceledHook = core.createEventHook();
    const onCommittedHook = core.createEventHook();
    const onStartHook = core.createEventHook();
    const onEndHook = core.createEventHook();
    const canUndo = vueDemi.ref(false);
    const canRedo = vueDemi.ref(false);
    const altPressed = vueDemi.ref(false);
    const shiftPressed = vueDemi.ref(false);
    const brush = vueDemi.ref({
      color: "black",
      size: 3,
      arrowEnd: false,
      cornerRadius: 0,
      dasharray: void 0,
      fill: "transparent",
      mode: "draw",
      ...options == null ? void 0 : options.brush
    });
    vueDemi.watch(brush, () => {
      const instance = drauuInstance.value;
      if (instance) {
        instance.brush = brush.value;
        instance.mode = brush.value.mode;
      }
    }, { deep: true });
    const undo = () => {
      var _a;
      return (_a = drauuInstance.value) == null ? void 0 : _a.undo();
    };
    const redo = () => {
      var _a;
      return (_a = drauuInstance.value) == null ? void 0 : _a.redo();
    };
    const clear = () => {
      var _a;
      return (_a = drauuInstance.value) == null ? void 0 : _a.clear();
    };
    const cancel = () => {
      var _a;
      return (_a = drauuInstance.value) == null ? void 0 : _a.cancel();
    };
    const load = (svg) => {
      var _a;
      return (_a = drauuInstance.value) == null ? void 0 : _a.load(svg);
    };
    const dump = () => {
      var _a;
      return (_a = drauuInstance.value) == null ? void 0 : _a.dump();
    };
    const cleanup = () => {
      var _a;
      disposables.forEach((dispose) => dispose());
      (_a = drauuInstance.value) == null ? void 0 : _a.unmount();
    };
    const syncStatus = () => {
      if (drauuInstance.value) {
        canUndo.value = drauuInstance.value.canUndo();
        canRedo.value = drauuInstance.value.canRedo();
        altPressed.value = drauuInstance.value.altPressed;
        shiftPressed.value = drauuInstance.value.shiftPressed;
      }
    };
    vueDemi.watch(
      () => core.unrefElement(target),
      (el) => {
        if (!el || typeof SVGSVGElement === "undefined" || !(el instanceof SVGSVGElement))
          return;
        if (drauuInstance.value)
          cleanup();
        drauuInstance.value = drauu.createDrauu({ el, ...options });
        syncStatus();
        disposables = [
          drauuInstance.value.on("canceled", () => onCanceledHook.trigger()),
          drauuInstance.value.on("committed", (node) => onCommittedHook.trigger(node)),
          drauuInstance.value.on("start", () => onStartHook.trigger()),
          drauuInstance.value.on("end", () => onEndHook.trigger()),
          drauuInstance.value.on("changed", () => {
            syncStatus();
            onChangedHook.trigger();
          })
        ];
      },
      { flush: "post" }
    );
    shared.tryOnScopeDispose(() => cleanup());
    return {
      drauuInstance,
      load,
      dump,
      clear,
      cancel,
      undo,
      redo,
      canUndo,
      canRedo,
      brush,
      onChanged: onChangedHook.on,
      onCommitted: onCommittedHook.on,
      onStart: onStartHook.on,
      onEnd: onEndHook.on,
      onCanceled: onCanceledHook.on
    };
  }

  exports.useDrauu = useDrauu;

})(this.VueUse = this.VueUse || {}, VueUse, VueUse, Drauu, VueDemi);
