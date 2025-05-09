'use strict';

var shared = require('@vueuse/shared');
var Fuse = require('fuse.js');
var vueDemi = require('vue-demi');

function useFuse(search, data, options) {
  const createFuse = () => {
    var _a, _b;
    return new Fuse(
      (_a = shared.toValue(data)) != null ? _a : [],
      (_b = shared.toValue(options)) == null ? void 0 : _b.fuseOptions
    );
  };
  const fuse = vueDemi.ref(createFuse());
  vueDemi.watch(
    () => {
      var _a;
      return (_a = shared.toValue(options)) == null ? void 0 : _a.fuseOptions;
    },
    () => {
      fuse.value = createFuse();
    },
    { deep: true }
  );
  vueDemi.watch(
    () => shared.toValue(data),
    (newData) => {
      fuse.value.setCollection(newData);
    },
    { deep: true }
  );
  const results = vueDemi.computed(() => {
    const resolved = shared.toValue(options);
    if ((resolved == null ? void 0 : resolved.matchAllWhenSearchEmpty) && !shared.toValue(search))
      return shared.toValue(data).map((item, index) => ({ item, refIndex: index }));
    const limit = resolved == null ? void 0 : resolved.resultLimit;
    return fuse.value.search(shared.toValue(search), limit ? { limit } : void 0);
  });
  return {
    fuse,
    results
  };
}

exports.useFuse = useFuse;
