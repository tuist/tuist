import { u as useHead } from './shared/vue.-sixQ7xP.mjs';
import { h as headSymbol } from './shared/vue.ziyDaVMR.mjs';
import 'vue';
import 'unhead';
import '@unhead/shared';

const UnheadPlugin = (_Vue) => {
  _Vue.config.optionMergeStrategies.head = function(toVal, fromVal) {
    return [toVal, fromVal].flat().filter(Boolean);
  };
  _Vue.mixin({
    created() {
      const head = this.$options.head;
      if (head) {
        if (Array.isArray(head)) {
          head.forEach((h) => {
            useHead(typeof h === "function" ? h.call(this) : h);
          });
        } else {
          useHead(typeof head === "function" ? head.call(this) : head);
        }
      }
    },
    beforeCreate() {
      const options = this.$options;
      if (options.unhead) {
        const origProvide = options.provide;
        options.provide = function() {
          let origProvideResult;
          if (typeof origProvide === "function")
            origProvideResult = origProvide.call(this);
          else
            origProvideResult = origProvide || {};
          return {
            ...origProvideResult,
            [headSymbol]: options.unhead
          };
        };
      }
    }
  });
};

export { UnheadPlugin };
