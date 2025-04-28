export type FetchWithProxyFallbackOptions = {
    proxy: string | undefined;
    /**
     * @see https://developer.mozilla.org/en-US/docs/Web/API/Request/cache
     */
    cache?: RequestInit['cache'];
};
/**
 * Fetches an OpenAPI document with a proxy fallback mechanism.
 *
 * If a proxy is provided and the URL requires it, it will first attempt to fetch using the proxy.
 * If the proxy fetch fails or is not used, it will fall back to a direct fetch.
 */
export declare function fetchWithProxyFallback(url: string, { proxy, cache }: FetchWithProxyFallbackOptions): Promise<Response>;
//# sourceMappingURL=fetchWithProxyFallback.d.ts.map