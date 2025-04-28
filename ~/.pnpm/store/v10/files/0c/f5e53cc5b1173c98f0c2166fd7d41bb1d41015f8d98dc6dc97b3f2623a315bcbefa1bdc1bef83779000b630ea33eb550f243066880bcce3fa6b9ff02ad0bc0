import type { ErrorResponse } from '../../../libs/errors.ts';
import type { Oauth2Flow, Server } from '@scalar/oas-utils/entities/spec';
/** Oauth2 security schemes which are not implicit */
type NonImplicitFlow = Exclude<Oauth2Flow, {
    type: 'implicit';
}>;
type PKCEState = {
    codeVerifier: string;
    codeChallenge: string;
    codeChallengeMethod: string;
};
/**
 * Creates a code challenge from the code verifier
 */
export declare const generateCodeChallenge: (verifier: string, encoding: "SHA-256" | "plain") => Promise<string>;
/**
 * Authorize oauth2 flow
 *
 * @returns the accessToken
 */
export declare const authorizeOauth2: (flow: Oauth2Flow, activeServer: Server, proxyUrl?: string) => Promise<ErrorResponse<string>>;
/**
 * Makes the BE authorization call to grab the token server to server
 * Used for clientCredentials and authorizationCode
 */
export declare const authorizeServers: (flow: NonImplicitFlow, scopes: string, { code, pkce, proxyUrl, }?: {
    code?: string;
    pkce?: PKCEState | null;
    proxyUrl?: string | undefined;
}) => Promise<ErrorResponse<string>>;
export {};
//# sourceMappingURL=oauth2.d.ts.map