/** Obviously local hostnames */
const LOCAL_HOSTNAMES = ['localhost', '127.0.0.1', '[::1]', '0.0.0.0'];
/**
 * Detect requests to localhost
 */
function isLocalUrl(url) {
    try {
        const { hostname } = new URL(url);
        return LOCAL_HOSTNAMES.includes(hostname);
    }
    catch {
        // If it’s not a valid URL, we can’t use the proxy anyway,
        // but it also covers cases like relative URLs (e.g. `openapi.json`).
        return true;
    }
}

export { isLocalUrl };
