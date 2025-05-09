import type { SecurityScheme } from '@scalar/oas-utils/entities/spec';
/**
 * Generates the headers, cookies and query params for selected security schemes
 * In the future we can add customization for where the security is applied
 */
export declare const buildRequestSecurity: (securitySchemes?: SecurityScheme[], env?: object, emptyTokenPlaceholder?: string) => {
    headers: Record<string, string>;
    cookies: {
        value: string;
        uid: string & import("zod").BRAND<"cookie">;
        name: string;
        path?: string | undefined;
        domain?: string | undefined;
    }[];
    urlParams: URLSearchParams;
};
//# sourceMappingURL=build-request-security.d.ts.map