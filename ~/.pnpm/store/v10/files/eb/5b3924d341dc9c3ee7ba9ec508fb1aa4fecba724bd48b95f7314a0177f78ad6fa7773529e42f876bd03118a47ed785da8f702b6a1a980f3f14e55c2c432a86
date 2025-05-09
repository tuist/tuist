/**
 * Normalizes a MIME type to a standard format.
 *
 * Input: application/problem+json; charset=utf-8
 * Output: application/json
 */
function normalizeMimeType(contentType) {
    if (typeof contentType !== 'string') {
        return undefined;
    }
    return contentType
        // Remove '; charset=utf-8'
        .replace(/;.*$/, '')
        // Remove 'problem+'
        .replace(/\/.+\+/, '/')
        // Remove whitespace
        .trim();
}

export { normalizeMimeType };
