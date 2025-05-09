/**
 * Merges multiple URLSearchParams objects, preserving multiple values per param
 * within each source, but later sources overwrite earlier ones completely
 * This should de-dupe our query params while allowing multiple keys for "arrays"
 */
export declare const mergeSearchParams: (...params: URLSearchParams[]) => URLSearchParams;
/** Combines a base URL and a path ensuring there's only one slash between them */
export declare const combineUrlAndPath: (url: string, path: string) => string;
/**
 * Creates a URL from the path and server
 * also optionally merges query params if you include urlSearchParams
 * This was re-written without using URL to support variables in the scheme
 */
export declare const mergeUrls: (url: string, path: string, urlParams?: URLSearchParams, disableOriginPrefix?: boolean) => string;
//# sourceMappingURL=merge-urls.d.ts.map