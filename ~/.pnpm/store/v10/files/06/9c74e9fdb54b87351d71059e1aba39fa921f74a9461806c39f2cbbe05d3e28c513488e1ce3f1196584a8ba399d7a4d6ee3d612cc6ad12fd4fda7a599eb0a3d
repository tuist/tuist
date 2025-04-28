'use strict';

const useHead = require('./shared/vue.BmMjB48i.cjs');
require('vue');
require('./shared/vue.DWlmwWrc.cjs');
require('unhead');
require('@unhead/shared');

function polyfillAsVueUseHead(head) {
  const polyfilled = head;
  polyfilled.headTags = head.resolveTags;
  polyfilled.addEntry = head.push;
  polyfilled.addHeadObjs = head.push;
  polyfilled.addReactiveEntry = (input, options) => {
    const api = useHead.useHead(input, options);
    if (api !== void 0)
      return api.dispose;
    return () => {
    };
  };
  polyfilled.removeHeadObjs = () => {
  };
  polyfilled.updateDOM = () => {
    head.hooks.callHook("entries:updated", head);
  };
  polyfilled.unhead = head;
  return polyfilled;
}

exports.polyfillAsVueUseHead = polyfillAsVueUseHead;
