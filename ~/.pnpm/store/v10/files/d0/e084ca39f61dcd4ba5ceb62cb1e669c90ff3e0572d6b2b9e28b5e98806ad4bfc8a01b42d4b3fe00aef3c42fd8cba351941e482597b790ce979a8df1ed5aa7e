'use strict';

var shared = require('@vueuse/shared');
var Schema = require('async-validator');
var vueDemi = require('vue-demi');

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
  const errors = vueDemi.computed(() => {
    var _a;
    return ((_a = errorInfo.value) == null ? void 0 : _a.errors) || [];
  });
  const errorFields = vueDemi.computed(() => {
    var _a;
    return ((_a = errorInfo.value) == null ? void 0 : _a.fields) || {};
  });
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

exports.useAsyncValidator = useAsyncValidator;
