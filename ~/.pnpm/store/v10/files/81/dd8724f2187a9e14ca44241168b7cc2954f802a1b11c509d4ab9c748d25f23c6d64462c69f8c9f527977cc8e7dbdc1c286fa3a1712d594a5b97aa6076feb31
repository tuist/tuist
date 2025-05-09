'use strict';

const useHead = require('./shared/vue.BmMjB48i.cjs');
const injectHead = require('./shared/vue.DWlmwWrc.cjs');
require('vue');
require('unhead');
require('@unhead/shared');

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
            useHead.useHead(typeof h === "function" ? h.call(this) : h);
          });
        } else {
          useHead.useHead(typeof head === "function" ? head.call(this) : head);
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
            [injectHead.headSymbol]: options.unhead
          };
        };
      }
    }
  });
};

exports.UnheadPlugin = UnheadPlugin;
