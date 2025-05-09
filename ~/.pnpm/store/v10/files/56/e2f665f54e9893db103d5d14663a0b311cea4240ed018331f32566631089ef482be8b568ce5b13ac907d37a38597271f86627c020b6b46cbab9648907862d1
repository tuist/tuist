// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
/**
 * Set a nested value from an object using a dot separated path.
 *
 * Basic Path: `'foo.bar'`
 *
 * With Array: `'foo.1.bar'`
 */
function setNestedValue(obj, path, value) {
    const keys = path.split('.');
    // Loop over to get the nested object reference. Then assign the value to it
    keys.reduce((acc, current, idx) => {
        if (idx === keys.length - 1)
            acc[current] = value;
        return acc[current];
    }, obj);
    return obj;
}
/**
 * Get a nested value from an object using a dot separated path.
 *
 * Basic Path: `'foo.bar'`
 *
 * With Array: `'foo.1.bar'`
 */
function getNestedValue(obj, path) {
    const keys = path.split('.');
    // Loop over to get the nested object reference. Then assign the value to it
    return keys.reduce((acc, current) => {
        return acc[current];
    }, obj);
}

export { getNestedValue, setNestedValue };
