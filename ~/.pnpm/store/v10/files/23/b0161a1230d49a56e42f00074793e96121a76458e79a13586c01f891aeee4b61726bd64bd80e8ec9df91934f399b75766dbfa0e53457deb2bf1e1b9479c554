import type { SecuritySchemePayload } from '@scalar/oas-utils/entities/spec';
export type SecuritySchemeOption = {
    id: string;
    label: string;
    isDeletable?: boolean;
    payload?: SecuritySchemePayload;
};
export type SecuritySchemeGroup = {
    label: string;
    options: SecuritySchemeOption[];
};
/**
 * Add auth options for Request Auth
 *
 * We store it as a dictionary first for quick lookups then convert to an array of options
 */
export declare const ADD_AUTH_DICT: {
    readonly apiKeyCookie: {
        readonly label: "API Key in Cookies";
        readonly payload: {
            readonly type: "apiKey";
            readonly in: "cookie";
            readonly nameKey: "apiKeyCookie";
        };
    };
    readonly apiKeyHeader: {
        readonly label: "API Key in Headers";
        readonly payload: {
            readonly type: "apiKey";
            readonly in: "header";
            readonly nameKey: "apiKeyHeader";
        };
    };
    readonly apiKeyQuery: {
        readonly label: "API Key in Query Params";
        readonly payload: {
            readonly type: "apiKey";
            readonly in: "query";
            readonly nameKey: "apiKeyQuery";
        };
    };
    readonly httpBasic: {
        readonly label: "HTTP Basic";
        readonly payload: {
            readonly type: "http";
            readonly scheme: "basic";
            readonly nameKey: "httpBasic";
        };
    };
    readonly httpBearer: {
        readonly label: "HTTP Bearer";
        readonly payload: {
            readonly type: "http";
            readonly scheme: "bearer";
            readonly nameKey: "httpBearer";
        };
    };
    readonly oauth2Implicit: {
        readonly label: "Oauth2 Implicit Flow";
        readonly payload: {
            readonly type: "oauth2";
            readonly nameKey: "oauth2Implicit";
            readonly flows: {
                readonly implicit: {
                    readonly type: "implicit";
                };
            };
        };
    };
    readonly oauth2Password: {
        readonly label: "Oauth2 Password Flow";
        readonly payload: {
            readonly type: "oauth2";
            readonly nameKey: "oauth2Password";
            readonly flows: {
                readonly password: {
                    readonly type: "password";
                };
            };
        };
    };
    readonly oauth2ClientCredentials: {
        readonly label: "Oauth2 Client Credentials";
        readonly payload: {
            readonly type: "oauth2";
            readonly nameKey: "oauth2ClientCredentials";
            readonly flows: {
                readonly clientCredentials: {
                    readonly type: "clientCredentials";
                };
            };
        };
    };
    readonly oauth2AuthorizationFlow: {
        readonly label: "Oauth2 Authorization Code";
        readonly payload: {
            readonly type: "oauth2";
            readonly nameKey: "oauth2AuthorizationFlow";
            readonly flows: {
                readonly authorizationCode: {
                    readonly type: "authorizationCode";
                };
            };
        };
    };
};
/** Options for the dropdown to add new auth */
export declare const ADD_AUTH_OPTIONS: SecuritySchemeOption[];
//# sourceMappingURL=new-auth-options.d.ts.map