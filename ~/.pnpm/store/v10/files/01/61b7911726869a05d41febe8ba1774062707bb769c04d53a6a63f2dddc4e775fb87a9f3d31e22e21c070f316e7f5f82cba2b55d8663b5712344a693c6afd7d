import type { RequestMethod, RequestParameterPayload } from '@scalar/oas-utils/entities/spec';
/** Define curlCommandResult type */
type CurlCommandResult = {
    method: RequestMethod;
    url: string;
    path: string;
    headers: Record<string, string>;
    servers?: Array<string>;
    requestBody?: {
        content: {
            [contentType: string]: {
                schema: {
                    type: string;
                    properties: Record<string, {
                        type: string;
                    }>;
                };
                example: Record<string, string>;
            };
        };
    };
    parameters: RequestParameterPayload[];
};
/** Make a usable object from a curl command to create a request */
export declare function importCurlCommand(curlCommand: string): CurlCommandResult;
export {};
//# sourceMappingURL=curl.d.ts.map