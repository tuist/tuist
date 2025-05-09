import type { RequestExample, RequestMethod } from '@scalar/oas-utils/entities/spec';
/**
 * Create the fetch request body from an example
 *
 * TODO: Should we be setting the content type headers here?
 * If so we must allow the user to override the content type header
 */
export declare function createFetchBody(method: RequestMethod, example: RequestExample, env: object): {
    body: URLSearchParams | FormData;
    contentType: string;
} | {
    body: string;
    contentType: "html" | "text" | "xml" | "json" | "javascript" | "yaml" | "edn" | undefined;
} | {
    body: Blob | undefined;
    contentType: string | undefined;
};
//# sourceMappingURL=create-fetch-body.d.ts.map