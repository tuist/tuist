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
;(function (exports, core, Sortable, vueDemi) {
  'use strict';

  function useSortable(el, list, options = {}) {
    let sortable;
    const { document = core.defaultDocument, ...resetOptions } = options;
    const defaultOptions = {
      onUpdate: (e) => {
        moveArrayElement(list, e.oldIndex, e.newIndex, e);
      }
    };
    const start = () => {
      const target = typeof el === "string" ? document == null ? void 0 : document.querySelector(el) : core.unrefElement(el);
      if (!target || sortable !== void 0)
        return;
      sortable = new Sortable(target, { ...defaultOptions, ...resetOptions });
    };
    const stop = () => {
      sortable == null ? void 0 : sortable.destroy();
      sortable = void 0;
    };
    const option = (name, value) => {
      if (value !== void 0)
        sortable == null ? void 0 : sortable.option(name, value);
      else
        return sortable == null ? void 0 : sortable.option(name);
    };
    core.tryOnMounted(start);
    core.tryOnScopeDispose(stop);
    return {
      stop,
      start,
      option
    };
  }
  function insertNodeAt(parentElement, element, index) {
    const refElement = parentElement.children[index];
    parentElement.insertBefore(element, refElement);
  }
  function removeNode(node) {
    if (node.parentNode)
      node.parentNode.removeChild(node);
  }
  function moveArrayElement(list, from, to, e = null) {
    if (e != null) {
      removeNode(e.item);
      insertNodeAt(e.from, e.item, from);
    }
    const _valueIsRef = vueDemi.isRef(list);
    const array = _valueIsRef ? [...core.toValue(list)] : core.toValue(list);
    if (to >= 0 && to < array.length) {
      const element = array.splice(from, 1)[0];
      vueDemi.nextTick(() => {
        array.splice(to, 0, element);
        if (_valueIsRef)
          list.value = array;
      });
    }
  }

  exports.insertNodeAt = insertNodeAt;
  exports.moveArrayElement = moveArrayElement;
  exports.removeNode = removeNode;
  exports.useSortable = useSortable;

})(this.VueUse = this.VueUse || {}, VueUse, Sortable, VueDemi);
