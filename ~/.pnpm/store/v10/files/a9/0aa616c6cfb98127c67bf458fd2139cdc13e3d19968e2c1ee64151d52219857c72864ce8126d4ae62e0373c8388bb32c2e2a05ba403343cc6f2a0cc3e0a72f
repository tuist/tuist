/**
 * Check if the value is a filesystem
 */
function isFilesystem(value) {
    return (typeof value !== 'undefined' &&
        Array.isArray(value) &&
        value.length > 0 &&
        value.some((file) => file.isEntrypoint === true));
}

export { isFilesystem };
