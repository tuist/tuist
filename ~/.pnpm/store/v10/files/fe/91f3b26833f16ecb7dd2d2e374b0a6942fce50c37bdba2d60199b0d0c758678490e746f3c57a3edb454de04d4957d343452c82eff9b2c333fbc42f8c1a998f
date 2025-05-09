import { inferSchemaFromExample } from './schemaHelpers.js';
import { extractStatusCodesFromTests } from './statusCodeHelpers.js';
/**
 * Extracts and converts Postman response objects to OpenAPI response objects.
 * Processes response status codes, descriptions, headers, and body content,
 * inferring schemas from example responses when possible.
 */
export function extractResponses(responses, item) {
    // Extract status codes from tests
    const statusCodes = item ? extractStatusCodesFromTests(item) : [];
    // Create a map of status codes to descriptions from responses
    const responseMap = responses.reduce((acc, response) => {
        const statusCode = response.code?.toString() || 'default';
        acc[statusCode] = {
            description: response.status || 'Successful response',
            headers: extractHeaders(response.header),
            content: {
                'application/json': {
                    schema: inferSchemaFromExample(response.body || ''),
                    examples: {
                        default: tryParseJson(response.body || ''),
                    },
                },
            },
        };
        return acc;
    }, {});
    // Add status codes from tests if not already present
    statusCodes.forEach((code) => {
        const codeStr = code.toString();
        if (!responseMap[codeStr]) {
            responseMap[codeStr] = {
                description: 'Successful response',
                content: {
                    'application/json': {},
                },
            };
        }
    });
    // If no responses and no status codes, return default 200
    if (Object.keys(responseMap).length === 0) {
        responseMap['200'] = {
            description: 'Successful response',
            content: {
                'application/json': {},
            },
        };
    }
    return responseMap;
}
function extractHeaders(headers) {
    if (!headers || typeof headers === 'string') {
        return undefined;
    }
    const openapiHeaders = {};
    if (Array.isArray(headers)) {
        headers.forEach((header) => {
            openapiHeaders[header.key] = {
                schema: {
                    type: 'string',
                    examples: [header.value],
                },
            };
        });
    }
    return openapiHeaders;
}
function tryParseJson(jsonString) {
    try {
        return JSON.parse(jsonString);
    }
    catch (_e) {
        return { rawContent: jsonString };
    }
}
