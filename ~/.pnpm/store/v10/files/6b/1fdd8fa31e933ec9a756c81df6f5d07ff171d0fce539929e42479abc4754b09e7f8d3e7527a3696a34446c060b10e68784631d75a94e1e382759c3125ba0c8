// @ts-nocheck
/**
 * Given a headers object retrieve a specific header out of it via a case-insensitive key.
 */
const getHeaderName = (headers, name) => Object.keys(headers).find((header) => header.toLowerCase() === name.toLowerCase());
/**
 * Given a headers object retrieve the contents of a header out of it via a case-insensitive key.
 */
const getHeader = (headers, name) => {
    const headerName = getHeaderName(headers, name);
    if (!headerName) {
        return undefined;
    }
    return headers[headerName];
};
/**
 * Determine if a given case-insensitive header exists within a header object.
 */
const hasHeader = (headers, name) => Boolean(getHeaderName(headers, name));

export { getHeader, getHeaderName, hasHeader };
