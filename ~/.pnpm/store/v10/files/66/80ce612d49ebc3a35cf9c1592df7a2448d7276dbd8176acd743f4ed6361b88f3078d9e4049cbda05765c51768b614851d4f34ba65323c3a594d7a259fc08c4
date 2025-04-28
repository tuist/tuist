'use strict';

var shared = require('@vueuse/shared');
var changeCase = require('change-case');
var vueDemi = require('vue-demi');

function _interopNamespaceDefault(e) {
  var n = Object.create(null);
  if (e) {
    Object.keys(e).forEach(function (k) {
      if (k !== 'default') {
        var d = Object.getOwnPropertyDescriptor(e, k);
        Object.defineProperty(n, k, d.get ? d : {
          enumerable: true,
          get: function () { return e[k]; }
        });
      }
    });
  }
  n.default = e;
  return Object.freeze(n);
}

var changeCase__namespace = /*#__PURE__*/_interopNamespaceDefault(changeCase);

const changeCaseTransforms = /* @__PURE__ */ Object.entries(changeCase__namespace).filter(([name, fn]) => typeof fn === "function" && name.endsWith("Case")).reduce((acc, [name, fn]) => {
  acc[name] = fn;
  return acc;
}, {});
function useChangeCase(input, type, options) {
  const typeRef = vueDemi.computed(() => {
    const t = shared.toValue(type);
    if (!changeCaseTransforms[t])
      throw new Error(`Invalid change case type "${t}"`);
    return t;
  });
  if (typeof input === "function")
    return vueDemi.computed(() => changeCaseTransforms[typeRef.value](shared.toValue(input), shared.toValue(options)));
  const text = vueDemi.ref(input);
  return vueDemi.computed({
    get() {
      return changeCaseTransforms[typeRef.value](text.value, shared.toValue(options));
    },
    set(value) {
      text.value = value;
    }
  });
}

exports.useChangeCase = useChangeCase;
