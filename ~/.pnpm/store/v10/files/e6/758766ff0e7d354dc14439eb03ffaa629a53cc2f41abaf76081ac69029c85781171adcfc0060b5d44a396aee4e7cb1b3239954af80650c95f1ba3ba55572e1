/**
 * Find an OpenAPI document URL in the HTML of @scalar/api-reference and other places.
 * This is useful to open the OpenAPI document from basically any source.
 */
export declare function resolve(value?: string | null, options?: {
    /**
     * Fetch function to use instead of the global fetch. Use this to intercept requests.
     */
    fetch?: (url: string) => Promise<Response>;
}): Promise<string | Record<string, any> | undefined>;
/**
 * Get the content between the script tags
 *
 * @example <script id="api-reference">console.log("Hello, world!");</script>
 */
export declare function getContentOfScriptTag(html: string): string | undefined;
/**
 * Get the configuration attribute from the script tag
 *
 * @example <script id="api-reference" data-configuration="{&quot;spec&quot;:{&quot;content&quot;:&quot;foo&quot;}}"></script>
 */
export declare function getConfigurationAttribute(html: string): string | undefined;
//# sourceMappingURL=resolve.d.ts.map