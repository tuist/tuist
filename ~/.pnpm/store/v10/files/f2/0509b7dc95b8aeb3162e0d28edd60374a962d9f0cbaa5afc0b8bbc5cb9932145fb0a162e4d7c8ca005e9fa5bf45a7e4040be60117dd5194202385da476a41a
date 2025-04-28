import { type ErrorResponse } from '../../libs/errors';
import type { EventBus } from '../../libs/event-bus';
import type { Cookie } from '@scalar/oas-utils/entities/cookie';
import type { Operation, RequestExample, ResponseInstance, SecurityScheme, Server } from '@scalar/oas-utils/entities/spec';
export type RequestStatus = 'start' | 'stop' | 'abort';
/** Response from sendRequest hoisted so we can use it as the return type for createRequestOperation */
type SendRequestResponse = Promise<ErrorResponse<{
    response: ResponseInstance;
    request: RequestExample;
    timestamp: number;
}>>;
/** Execute the request */
export declare const createRequestOperation: ({ environment, example, globalCookies, proxyUrl, request, securitySchemes, selectedSecuritySchemeUids, server, status, }: {
    environment: object | undefined;
    example: RequestExample;
    globalCookies: Cookie[];
    proxyUrl: string | undefined;
    request: Operation;
    securitySchemes: Record<string, SecurityScheme>;
    selectedSecuritySchemeUids?: Operation["selectedSecuritySchemeUids"];
    server?: Server | undefined;
    status?: EventBus<RequestStatus>;
}) => ErrorResponse<{
    controller: AbortController;
    sendRequest: () => SendRequestResponse;
    request: Request;
}>;
export {};
//# sourceMappingURL=create-request-operation.d.ts.map