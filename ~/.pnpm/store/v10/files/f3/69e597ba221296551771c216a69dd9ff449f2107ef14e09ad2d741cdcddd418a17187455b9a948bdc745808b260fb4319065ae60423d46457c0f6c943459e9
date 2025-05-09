import { shouldUseProxy, redirectToProxy } from './redirectToProxy.js';

/**
 * Fetches an OpenAPI document with a proxy fallback mechanism.
 *
 * If a proxy is provided and the URL requires it, it will first attempt to fetch using the proxy.
 * If the proxy fetch fails or is not used, it will fall back to a direct fetch.
 */
async function fetchWithProxyFallback(url, { proxy, cache }) {
    const fetchOptions = {
        cache: cache || 'default',
    };
    const shouldTryProxy = shouldUseProxy(proxy, url);
    const initialUrl = shouldTryProxy ? redirectToProxy(proxy, url) : url;
    try {
        const result = await fetch(initialUrl, fetchOptions);
        if (result.ok || !shouldTryProxy) {
            return result;
        }
        // Retry without proxy if the initial request failed
        return await fetch(url, fetchOptions);
    }
    catch (error) {
        if (shouldTryProxy) {
            // If proxy failed, try without it
            return await fetch(url, fetchOptions);
        }
        throw error;
    }
}

export { fetchWithProxyFallback };
