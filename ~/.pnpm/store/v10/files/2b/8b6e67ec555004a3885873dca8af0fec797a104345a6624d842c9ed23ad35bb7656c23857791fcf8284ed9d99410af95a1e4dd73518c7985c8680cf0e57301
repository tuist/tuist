'use strict';

function asArray(input) {
  return Array.isArray(input) ? input : [input];
}
const InternalKeySymbol = "_$key";
function packObject(input, options) {
  const keys = Object.keys(input);
  let [k, v] = keys;
  options = options || {};
  options.key = options.key || k;
  options.value = options.value || v;
  options.resolveKey = options.resolveKey || ((k2) => k2);
  const resolveKey = (index) => {
    const arr = asArray(options[index]);
    return arr.find((k2) => {
      if (typeof k2 === "string" && k2.includes(".")) {
        return k2;
      }
      return k2 && keys.includes(k2);
    });
  };
  const resolveValue = (k2, input2) => {
    if (k2.includes(".")) {
      const paths = k2.split(".");
      let val = input2;
      for (const path of paths)
        val = val[path];
      return val;
    }
    return input2[k2];
  };
  k = resolveKey("key") || k;
  v = resolveKey("value") || v;
  const dedupeKeyPrefix = input.key ? `${InternalKeySymbol}${input.key}-` : "";
  let keyValue = resolveValue(k, input);
  keyValue = options.resolveKey(keyValue);
  return {
    [`${dedupeKeyPrefix}${keyValue}`]: resolveValue(v, input)
  };
}

function packArray(input, options) {
  const packed = {};
  for (const i of input) {
    const packedObj = packObject(i, options);
    const pKey = Object.keys(packedObj)[0];
    const isDedupeKey = pKey.startsWith(InternalKeySymbol);
    if (!isDedupeKey && packed[pKey]) {
      packed[pKey] = Array.isArray(packed[pKey]) ? packed[pKey] : [packed[pKey]];
      packed[pKey].push(Object.values(packedObj)[0]);
    } else {
      packed[isDedupeKey ? pKey.split("-").slice(1).join("-") || pKey : pKey] = packedObj[pKey];
    }
  }
  return packed;
}

function packString(input) {
  const output = {};
  input.split(" ").forEach(
    (item) => {
      const val = item.replace(/"/g, "").split("=");
      output[val[0]] = val[1];
    }
  );
  return output;
}

function unpackToArray(input, options) {
  const unpacked = [];
  const kFn = options.resolveKeyData || ((ctx) => ctx.key);
  const vFn = options.resolveValueData || ((ctx) => ctx.value);
  for (const [k, v] of Object.entries(input)) {
    unpacked.push(...(Array.isArray(v) ? v : [v]).map((i) => {
      const ctx = { key: k, value: i };
      const val = vFn(ctx);
      if (typeof val === "object")
        return unpackToArray(val, options);
      if (Array.isArray(val))
        return val;
      return {
        [typeof options.key === "function" ? options.key(ctx) : options.key]: kFn(ctx),
        [typeof options.value === "function" ? options.value(ctx) : options.value]: val
      };
    }).flat());
  }
  return unpacked;
}

function unpackToString(value, options) {
  return Object.entries(value).map(([key, value2]) => {
    if (typeof value2 === "object")
      value2 = unpackToString(value2, options);
    if (options.resolve) {
      const resolved = options.resolve({ key, value: value2 });
      if (typeof resolved !== "undefined")
        return resolved;
    }
    if (typeof value2 === "number")
      value2 = value2.toString();
    if (typeof value2 === "string" && options.wrapValue) {
      value2 = value2.replace(new RegExp(options.wrapValue, "g"), `\\${options.wrapValue}`);
      value2 = `${options.wrapValue}${value2}${options.wrapValue}`;
    }
    return `${key}${options.keyValueSeparator || ""}${value2}`;
  }).join(options.entrySeparator || "");
}

exports.InternalKeySymbol = InternalKeySymbol;
exports.packArray = packArray;
exports.packObject = packObject;
exports.packString = packString;
exports.unpackToArray = unpackToArray;
exports.unpackToString = unpackToString;
