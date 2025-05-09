// src/array.ts
function toArray(v) {
  if (!v) return [];
  return Array.isArray(v) ? v : [v];
}
var fromLength = (length) => Array.from(Array(length).keys());
var first = (v) => v[0];
var last = (v) => v[v.length - 1];
var isEmpty = (v) => v.length === 0;
var has = (v, t) => v.indexOf(t) !== -1;
var add = (v, ...items) => v.concat(items);
var remove = (v, ...items) => v.filter((t) => !items.includes(t));
var removeAt = (v, i) => v.filter((_, idx) => idx !== i);
var insertAt = (v, i, ...items) => [...v.slice(0, i), ...items, ...v.slice(i)];
var uniq = (v) => Array.from(new Set(v));
var addOrRemove = (v, item) => {
  if (has(v, item)) return remove(v, item);
  return add(v, item);
};
function clear(v) {
  while (v.length > 0) v.pop();
  return v;
}
function nextIndex(v, idx, opts = {}) {
  const { step = 1, loop = true } = opts;
  const next2 = idx + step;
  const len = v.length;
  const last2 = len - 1;
  if (idx === -1) return step > 0 ? 0 : last2;
  if (next2 < 0) return loop ? last2 : 0;
  if (next2 >= len) return loop ? 0 : idx > len ? len : idx;
  return next2;
}
function next(v, idx, opts = {}) {
  return v[nextIndex(v, idx, opts)];
}
function prevIndex(v, idx, opts = {}) {
  const { step = 1, loop = true } = opts;
  return nextIndex(v, idx, { step: -step, loop });
}
function prev(v, index, opts = {}) {
  return v[prevIndex(v, index, opts)];
}
var chunk = (v, size) => {
  const res = [];
  return v.reduce((rows, value, index) => {
    if (index % size === 0) rows.push([value]);
    else last(rows)?.push(value);
    return rows;
  }, res);
};
function flatArray(arr) {
  return arr.reduce((flat, item) => {
    if (Array.isArray(item)) {
      return flat.concat(flatArray(item));
    }
    return flat.concat(item);
  }, []);
}

// src/equal.ts
var isArrayLike = (value) => value?.constructor.name === "Array";
var isArrayEqual = (a, b) => {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (!isEqual(a[i], b[i])) return false;
  }
  return true;
};
var isEqual = (a, b) => {
  if (Object.is(a, b)) return true;
  if (a == null && b != null || a != null && b == null) return false;
  if (typeof a?.isEqual === "function" && typeof b?.isEqual === "function") {
    return a.isEqual(b);
  }
  if (typeof a === "function" && typeof b === "function") {
    return a.toString() === b.toString();
  }
  if (isArrayLike(a) && isArrayLike(b)) {
    return isArrayEqual(Array.from(a), Array.from(b));
  }
  if (!(typeof a === "object") || !(typeof b === "object")) return false;
  const keys = Object.keys(b ?? /* @__PURE__ */ Object.create(null));
  const length = keys.length;
  for (let i = 0; i < length; i++) {
    const hasKey = Reflect.has(a, keys[i]);
    if (!hasKey) return false;
  }
  for (let i = 0; i < length; i++) {
    const key = keys[i];
    if (!isEqual(a[key], b[key])) return false;
  }
  return true;
};

// src/guard.ts
var isDev = () => process.env.NODE_ENV !== "production";
var isArray = (v) => Array.isArray(v);
var isBoolean = (v) => v === true || v === false;
var isObjectLike = (v) => v != null && typeof v === "object";
var isObject = (v) => isObjectLike(v) && !isArray(v);
var isNumber = (v) => typeof v === "number" && !Number.isNaN(v);
var isString = (v) => typeof v === "string";
var isFunction = (v) => typeof v === "function";
var isNull = (v) => v == null;
var hasProp = (obj, prop) => Object.prototype.hasOwnProperty.call(obj, prop);
var baseGetTag = (v) => Object.prototype.toString.call(v);
var fnToString = Function.prototype.toString;
var objectCtorString = fnToString.call(Object);
var isPlainObject = (v) => {
  if (!isObjectLike(v) || baseGetTag(v) != "[object Object]") return false;
  const proto = Object.getPrototypeOf(v);
  if (proto === null) return true;
  const Ctor = hasProp(proto, "constructor") && proto.constructor;
  return typeof Ctor == "function" && Ctor instanceof Ctor && fnToString.call(Ctor) == objectCtorString;
};

// src/functions.ts
var runIfFn = (v, ...a) => {
  const res = typeof v === "function" ? v(...a) : v;
  return res ?? void 0;
};
var cast = (v) => v;
var identity = (v) => v();
var noop = () => {
};
var callAll = (...fns) => (...a) => {
  fns.forEach(function(fn) {
    fn?.(...a);
  });
};
var uuid = /* @__PURE__ */ (() => {
  let id = 0;
  return () => {
    id++;
    return id.toString(36);
  };
})();
function match(key, record, ...args) {
  if (key in record) {
    const fn = record[key];
    return isFunction(fn) ? fn(...args) : fn;
  }
  const error = new Error(`No matching key: ${JSON.stringify(key)} in ${JSON.stringify(Object.keys(record))}`);
  Error.captureStackTrace?.(error, match);
  throw error;
}
var tryCatch = (fn, fallback) => {
  try {
    return fn();
  } catch (error) {
    if (error instanceof Error) {
      Error.captureStackTrace?.(error, tryCatch);
    }
    return fallback?.();
  }
};
function throttle(fn, wait = 0) {
  let lastCall = 0;
  let timeout = null;
  return (...args) => {
    const now = Date.now();
    const timeSinceLastCall = now - lastCall;
    if (timeSinceLastCall >= wait) {
      if (timeout) {
        clearTimeout(timeout);
        timeout = null;
      }
      fn(...args);
      lastCall = now;
    } else if (!timeout) {
      timeout = setTimeout(() => {
        fn(...args);
        lastCall = Date.now();
        timeout = null;
      }, wait - timeSinceLastCall);
    }
  };
}

// src/number.ts
var { floor, abs, round, min, max, pow, sign } = Math;
var isNaN = (v) => Number.isNaN(v);
var nan = (v) => isNaN(v) ? 0 : v;
var mod = (v, m) => (v % m + m) % m;
var wrap = (v, vmax) => (v % vmax + vmax) % vmax;
var getMinValueAtIndex = (i, v, vmin) => i === 0 ? vmin : v[i - 1];
var getMaxValueAtIndex = (i, v, vmax) => i === v.length - 1 ? vmax : v[i + 1];
var isValueAtMax = (v, vmax) => nan(v) >= vmax;
var isValueAtMin = (v, vmin) => nan(v) <= vmin;
var isValueWithinRange = (v, vmin, vmax) => nan(v) >= vmin && nan(v) <= vmax;
var roundValue = (v, vmin, step) => round((nan(v) - vmin) / step) * step + vmin;
var clampValue = (v, vmin, vmax) => min(max(nan(v), vmin), vmax);
var clampPercent = (v) => clampValue(v, 0, 1);
var getValuePercent = (v, vmin, vmax) => (nan(v) - vmin) / (vmax - vmin);
var getPercentValue = (p, vmin, vmax, step) => clampValue(roundValue(p * (vmax - vmin) + vmin, vmin, step), vmin, vmax);
var roundToStepPrecision = (v, step) => {
  let rv = v;
  let ss = step.toString();
  let pi = ss.indexOf(".");
  let p = pi >= 0 ? ss.length - pi : 0;
  if (p > 0) {
    let pw = pow(10, p);
    rv = round(rv * pw) / pw;
  }
  return rv;
};
var roundToDpr = (v, dpr) => typeof dpr === "number" ? floor(v * dpr + 0.5) / dpr : round(v);
var snapValueToStep = (v, vmin, vmax, step) => {
  vmin = Number(vmin);
  vmax = Number(vmax);
  let remainder = (v - (isNaN(vmin) ? 0 : vmin)) % step;
  let sv = roundToStepPrecision(
    abs(remainder) * 2 >= step ? v + sign(remainder) * (step - abs(remainder)) : v - remainder,
    step
  );
  if (!isNaN(vmin)) {
    if (sv < vmin) {
      sv = vmin;
    } else if (!isNaN(vmax) && sv > vmax) {
      sv = vmin + floor(roundToStepPrecision((vmax - vmin) / step, step)) * step;
    }
  } else if (!isNaN(vmax) && sv > vmax) {
    sv = vmin + floor(roundToStepPrecision((vmax - vmin) / step, step)) * step;
  }
  return roundToStepPrecision(sv, step);
};
var setValueAtIndex = (vs, i, v) => {
  if (vs[i] === v) return vs;
  return [...vs.slice(0, i), v, ...vs.slice(i + 1)];
};
function getValueSetterAtIndex(index, ctx) {
  const minValueAtIndex = getMinValueAtIndex(index, ctx.values, ctx.min);
  const maxValueAtIndex = getMaxValueAtIndex(index, ctx.values, ctx.max);
  let nextValues = ctx.values.slice();
  return function setValue(value) {
    let nextValue = snapValueToStep(value, minValueAtIndex, maxValueAtIndex, ctx.step);
    nextValues = setValueAtIndex(nextValues, index, value);
    nextValues[index] = nextValue;
    return nextValues;
  };
}
function getNextStepValue(index, ctx) {
  const nextValue = ctx.values[index] + ctx.step;
  return getValueSetterAtIndex(index, ctx)(nextValue);
}
function getPreviousStepValue(index, ctx) {
  const nextValue = ctx.values[index] - ctx.step;
  return getValueSetterAtIndex(index, ctx)(nextValue);
}
var getClosestValueIndex = (vs, t) => {
  let i = vs.findIndex((v) => t - v < 0);
  if (i === 0) return i;
  if (i === -1) return vs.length - 1;
  let vLeft = vs[i - 1];
  let vRight = vs[i];
  if (abs(vLeft - t) < abs(vRight - t)) return i - 1;
  return i;
};
var getClosestValue = (vs, t) => vs[getClosestValueIndex(vs, t)];
var getValueRanges = (vs, vmin, vmax, gap) => vs.map((v, i) => ({
  min: i === 0 ? vmin : vs[i - 1] + gap,
  max: i === vs.length - 1 ? vmax : vs[i + 1] - gap,
  value: v
}));
var getValueTransformer = (va, vb) => {
  const [a, b] = va;
  const [c, d] = vb;
  return (v) => a === b || c === d ? c : c + (d - c) / (b - a) * (v - a);
};
var toFixedNumber = (v, d = 0, b = 10) => {
  const pow2 = Math.pow(b, d);
  return round(v * pow2) / pow2;
};
var countDecimals = (value) => {
  if (!Number.isFinite(value)) return 0;
  let e = 1, p = 0;
  while (Math.round(value * e) / e !== value) {
    e *= 10;
    p += 1;
  }
  return p;
};
var decimalOp = (a, op, b) => {
  let result = op === "+" ? a + b : a - b;
  if (a % 1 !== 0 || b % 1 !== 0) {
    const multiplier = 10 ** Math.max(countDecimals(a), countDecimals(b));
    a = Math.round(a * multiplier);
    b = Math.round(b * multiplier);
    result = op === "+" ? a + b : a - b;
    result /= multiplier;
  }
  return result;
};
var incrementValue = (v, s) => decimalOp(nan(v), "+", s);
var decrementValue = (v, s) => decimalOp(nan(v), "-", s);
var toPx = (v) => v != null ? `${v}px` : void 0;

// src/object.ts
function compact(obj) {
  if (!isPlainObject2(obj) || obj === void 0) return obj;
  const keys = Reflect.ownKeys(obj).filter((key) => typeof key === "string");
  const filtered = {};
  for (const key of keys) {
    const value = obj[key];
    if (value !== void 0) {
      filtered[key] = compact(value);
    }
  }
  return filtered;
}
var json = (v) => JSON.parse(JSON.stringify(v));
var isPlainObject2 = (v) => {
  return v && typeof v === "object" && v.constructor === Object;
};
function pick(obj, keys) {
  const filtered = {};
  for (const key of keys) {
    const value = obj[key];
    if (value !== void 0) {
      filtered[key] = value;
    }
  }
  return filtered;
}
function splitProps(props, keys) {
  const rest = {};
  const result = {};
  const keySet = new Set(keys);
  for (const key in props) {
    if (keySet.has(key)) {
      result[key] = props[key];
    } else {
      rest[key] = props[key];
    }
  }
  return [result, rest];
}
var createSplitProps = (keys) => {
  return function split(props) {
    return splitProps(props, keys);
  };
};
function omit(obj, keys) {
  return createSplitProps(keys)(obj)[1];
}

// src/timers.ts
function setRafInterval(callback, interval) {
  let start = performance.now();
  let handle;
  function loop(now) {
    handle = requestAnimationFrame(loop);
    const delta = now - start;
    if (delta >= interval) {
      start = now - delta % interval;
      callback({ startMs: start, deltaMs: delta });
    }
  }
  handle = requestAnimationFrame(loop);
  return () => cancelAnimationFrame(handle);
}
function setRafTimeout(callback, delay) {
  const start = performance.now();
  let handle;
  function loop(now) {
    handle = requestAnimationFrame(loop);
    const delta = now - start;
    if (delta >= delay) {
      callback();
    }
  }
  handle = requestAnimationFrame(loop);
  return () => cancelAnimationFrame(handle);
}

// src/warning.ts
function warn(...a) {
  const m = a.length === 1 ? a[0] : a[1];
  const c = a.length === 2 ? a[0] : true;
  if (c && process.env.NODE_ENV !== "production") {
    console.warn(m);
  }
}
function invariant(...a) {
  const m = a.length === 1 ? a[0] : a[1];
  const c = a.length === 2 ? a[0] : true;
  if (c && process.env.NODE_ENV !== "production") {
    throw new Error(m);
  }
}
function ensure(c, m) {
  if (c == null) throw new Error(m());
}
function ensureProps(props, keys, scope) {
  let missingKeys = [];
  for (const key of keys) {
    if (props[key] == null) missingKeys.push(key);
  }
  if (missingKeys.length > 0)
    throw new Error(`[zag-js${scope ? ` > ${scope}` : ""}] missing required props: ${missingKeys.join(", ")}`);
}

export { add, addOrRemove, callAll, cast, chunk, clampPercent, clampValue, clear, compact, createSplitProps, decrementValue, ensure, ensureProps, first, flatArray, fromLength, getClosestValue, getClosestValueIndex, getMaxValueAtIndex, getMinValueAtIndex, getNextStepValue, getPercentValue, getPreviousStepValue, getValuePercent, getValueRanges, getValueSetterAtIndex, getValueTransformer, has, hasProp, identity, incrementValue, insertAt, invariant, isArray, isBoolean, isDev, isEmpty, isEqual, isFunction, isNaN, isNull, isNumber, isObject, isObjectLike, isPlainObject, isString, isValueAtMax, isValueAtMin, isValueWithinRange, json, last, match, mod, nan, next, nextIndex, noop, omit, pick, prev, prevIndex, remove, removeAt, roundToDpr, roundToStepPrecision, roundValue, runIfFn, setRafInterval, setRafTimeout, setValueAtIndex, snapValueToStep, splitProps, throttle, toArray, toFixedNumber, toPx, tryCatch, uniq, uuid, warn, wrap };
