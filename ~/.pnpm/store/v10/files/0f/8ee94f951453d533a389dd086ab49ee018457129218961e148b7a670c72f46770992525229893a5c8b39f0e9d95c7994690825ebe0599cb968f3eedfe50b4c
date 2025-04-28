'use strict';

var vueDemi = require('vue-demi');
var shared = require('@vueuse/shared');
var Schema = require('async-validator');

const AsyncValidatorSchema = Schema.default || Schema;
function useAsyncValidator(value, rules, options = {}) {
  const {
    validateOption = {},
    immediate = true,
    manual = false
  } = options;
  const valueRef = shared.toRef(value);
  const errorInfo = vueDemi.shallowRef(null);
  const isFinished = vueDemi.ref(true);
  const pass = vueDemi.ref(!immediate || manual);
  const errors = vueDemi.computed(() => errorInfo.value?.errors || []);
  const errorFields = vueDemi.computed(() => errorInfo.value?.fields || {});
  const validator = vueDemi.computed(() => new AsyncValidatorSchema(shared.toValue(rules)));
  const execute = async () => {
    isFinished.value = false;
    pass.value = false;
    try {
      await validator.value.validate(valueRef.value, validateOption);
      pass.value = true;
      errorInfo.value = null;
    } catch (err) {
      errorInfo.value = err;
    } finally {
      isFinished.value = true;
    }
    return {
      pass: pass.value,
      errorInfo: errorInfo.value,
      errors: errors.value,
      errorFields: errorFields.value
    };
  };
  if (!manual) {
    vueDemi.watch(
      [valueRef, validator],
      () => execute(),
      { immediate, deep: true }
    );
  }
  const shell = {
    isFinished,
    pass,
    errors,
    errorInfo,
    errorFields,
    execute
  };
  function waitUntilFinished() {
    return new Promise((resolve, reject) => {
      shared.until(isFinished).toBe(true).then(() => resolve(shell)).catch((error) => reject(error));
    });
  }
  return {
    ...shell,
    then(onFulfilled, onRejected) {
      return waitUntilFinished().then(onFulfilled, onRejected);
    }
  };
}

const UseAsyncValidator = /* @__PURE__ */ /* #__PURE__ */ vueDemi.defineComponent({
  name: "UseAsyncValidator",
  props: {
    form: {
      type: Object,
      required: true
    },
    rules: {
      type: Object,
      required: true
    }
  },
  setup(props, { slots }) {
    const data = vueDemi.reactive(useAsyncValidator(props.form, props.rules));
    return () => {
      if (slots.default)
        return slots.default(data);
    };
  }
});

exports.UseAsyncValidator = UseAsyncValidator;
