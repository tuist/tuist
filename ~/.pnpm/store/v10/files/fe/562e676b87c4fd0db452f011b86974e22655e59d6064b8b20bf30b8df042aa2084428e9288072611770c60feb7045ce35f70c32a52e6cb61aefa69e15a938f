'use strict';

var core = require('@vueuse/core');
var focusTrap = require('focus-trap');
var vueDemi = require('vue-demi');

const UseFocusTrap = /* @__PURE__ */ /* #__PURE__ */ vueDemi.defineComponent({
  name: "UseFocusTrap",
  props: ["as", "options"],
  setup(props, { slots }) {
    let trap;
    const target = vueDemi.ref();
    const activate = () => trap && trap.activate();
    const deactivate = () => trap && trap.deactivate();
    vueDemi.watch(
      () => core.unrefElement(target),
      (el) => {
        if (!el)
          return;
        trap = focusTrap.createFocusTrap(el, props.options || {});
        activate();
      },
      { flush: "post" }
    );
    vueDemi.onScopeDispose(() => deactivate());
    return () => {
      if (slots.default)
        return vueDemi.h(props.as || "div", { ref: target }, slots.default());
    };
  }
});

exports.UseFocusTrap = UseFocusTrap;
