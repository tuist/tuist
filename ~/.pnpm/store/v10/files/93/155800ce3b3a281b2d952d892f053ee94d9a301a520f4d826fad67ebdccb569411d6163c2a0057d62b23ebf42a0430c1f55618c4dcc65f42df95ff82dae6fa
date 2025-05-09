import type { Operation, RequestExample } from '@scalar/oas-utils/entities/spec';
import type { HarRequest } from '@scalar/snippetz';
type Props = {
    baseUrl: string | undefined;
    body?: RequestExample['body'] | undefined;
    cookies: {
        key: string;
        value: string;
        enabled: boolean;
    }[];
    headers: {
        key: string;
        value: string;
        enabled: boolean;
    }[];
    query: {
        key: string;
        value: string;
        enabled: boolean;
    }[];
} & Pick<Operation, 'method' | 'path'>;
/**
 * Takes in a regular request object and returns a HAR request
 * We also Titlecase the headers and remove accept header if it's *
 */
export declare const convertToHarRequest: ({ baseUrl, method, body, path, cookies, headers, query, }: Props) => HarRequest;
export {};
//# sourceMappingURL=convert-to-har-request.d.ts.map