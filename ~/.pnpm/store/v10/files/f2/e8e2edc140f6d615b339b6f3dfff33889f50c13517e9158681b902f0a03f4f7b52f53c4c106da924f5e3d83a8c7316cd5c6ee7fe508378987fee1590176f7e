"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.merge = void 0;
// istanbul ignore next
const isObject = (obj) => {
    if (typeof obj === "object" && obj !== null) {
        if (typeof Object.getPrototypeOf === "function") {
            const prototype = Object.getPrototypeOf(obj);
            return prototype === Object.prototype || prototype === null;
        }
        return Object.prototype.toString.call(obj) === "[object Object]";
    }
    return false;
};
const merge = (...objects) => objects.reduce((result, current) => {
    if (Array.isArray(current)) {
        throw new TypeError("Arguments provided to ts-deepmerge must be objects, not arrays.");
    }
    Object.keys(current).forEach((key) => {
        if (["__proto__", "constructor", "prototype"].includes(key)) {
            return;
        }
        if (Array.isArray(result[key]) && Array.isArray(current[key])) {
            result[key] = exports.merge.options.mergeArrays
                ? exports.merge.options.uniqueArrayItems
                    ? Array.from(new Set(result[key].concat(current[key])))
                    : [...result[key], ...current[key]]
                : current[key];
        }
        else if (isObject(result[key]) && isObject(current[key])) {
            result[key] = (0, exports.merge)(result[key], current[key]);
        }
        else {
            result[key] =
                current[key] === undefined
                    ? exports.merge.options.allowUndefinedOverrides
                        ? current[key]
                        : result[key]
                    : current[key];
        }
    });
    return result;
}, {});
exports.merge = merge;
const defaultOptions = {
    allowUndefinedOverrides: true,
    mergeArrays: true,
    uniqueArrayItems: true,
};
exports.merge.options = defaultOptions;
exports.merge.withOptions = (options, ...objects) => {
    exports.merge.options = Object.assign(Object.assign({}, defaultOptions), options);
    const result = (0, exports.merge)(...objects);
    exports.merge.options = defaultOptions;
    return result;
};
