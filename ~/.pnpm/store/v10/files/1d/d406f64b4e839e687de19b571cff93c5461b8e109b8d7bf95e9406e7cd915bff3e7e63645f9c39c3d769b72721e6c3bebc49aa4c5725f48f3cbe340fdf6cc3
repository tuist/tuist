/**
 * Converts an array of name/value pairs into an object with those mappings
 *
 * @example
 * arrayToObject([{ name: 'foo', value: 'bar' }]) // => { foo: 'bar' }
 */
function arrayToObject(items) {
    return items.reduce((acc, item) => {
        acc[item.name] = item.value;
        return acc;
    }, {});
}

export { arrayToObject };
