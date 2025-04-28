'use strict';

const vue = require('vue');
const injectHead = require('./vue.DWlmwWrc.cjs');

function useHead(input, options = {}) {
  const head = options.head || injectHead.injectHead();
  if (head) {
    if (!head.ssr)
      return clientUseHead(head, input, options);
    return head.push(input, options);
  }
}
function clientUseHead(head, input, options = {}) {
  const deactivated = vue.ref(false);
  const resolvedInput = vue.ref({});
  vue.watchEffect(() => {
    resolvedInput.value = deactivated.value ? {} : injectHead.resolveUnrefHeadInput(input);
  });
  const entry = head.push(resolvedInput.value, options);
  vue.watch(resolvedInput, (e) => {
    entry.patch(e);
  });
  const vm = vue.getCurrentInstance();
  if (vm) {
    vue.onBeforeUnmount(() => {
      entry.dispose();
    });
    vue.onDeactivated(() => {
      deactivated.value = true;
    });
    vue.onActivated(() => {
      deactivated.value = false;
    });
  }
  return entry;
}

exports.useHead = useHead;
