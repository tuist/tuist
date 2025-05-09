// TODO: This is a copy of packages/core-interface/src/database/utility.ts
/**
 * Overwrite a target object a new replacement object handling removed keys
 */
function objectMerge(target, replacement) {
    // Clear any keys that have been removed in the replacement
    Object.keys(target).forEach((key) => {
        if (!Object.hasOwn(replacement, key)) {
            delete target[key];
        }
    });
    Object.assign(target, replacement);
    return target;
}
/**
 * Type safe version of Object.keys
 * Can probably remove this whenever typescript adds it
 */
const getObjectKeys = (obj) => Object.keys(obj);

export { getObjectKeys, objectMerge };
