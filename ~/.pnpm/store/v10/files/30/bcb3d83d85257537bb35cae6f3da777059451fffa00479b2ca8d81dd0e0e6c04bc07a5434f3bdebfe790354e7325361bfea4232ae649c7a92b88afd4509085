import { processFormDataSchema } from './formDataHelpers.js';
import { createParameterObject } from './parameterHelpers.js';
/**
 * Extracts and converts the request body from a Postman request to an OpenAPI RequestBodyObject.
 * Handles raw JSON, form-data, and URL-encoded body types, creating appropriate schemas and content types.
 */
export function extractRequestBody(body) {
    const requestBody = {
        content: {},
    };
    if (body.mode === 'raw') {
        handleRawBody(body, requestBody);
        return requestBody;
    }
    if (body.mode === 'formdata' && body.formdata) {
        handleFormDataBody(body.formdata, requestBody);
        return requestBody;
    }
    if (body.mode === 'urlencoded' && body.urlencoded) {
        handleUrlEncodedBody(body.urlencoded, requestBody);
        return requestBody;
    }
    return requestBody;
}
function handleRawBody(body, requestBody) {
    try {
        const jsonBody = JSON.parse(body.raw || '');
        requestBody.content = {
            'application/json': {
                schema: {
                    type: 'object',
                    example: jsonBody,
                },
            },
        };
    }
    catch (_error) {
        requestBody.content = {
            'text/plain': {
                schema: {
                    type: 'string',
                    examples: [body.raw],
                },
            },
        };
    }
}
function handleFormDataBody(formdata, requestBody) {
    requestBody.content = {
        'multipart/form-data': {
            schema: processFormDataSchema(formdata),
        },
    };
}
function handleUrlEncodedBody(urlencoded, requestBody) {
    const schema = {
        type: 'object',
        properties: {},
        required: [],
    };
    urlencoded.forEach((item) => {
        if (schema.properties) {
            const paramObject = createParameterObject(item, 'query');
            schema.properties[item.key] = {
                type: 'string',
                examples: [item.value],
                description: paramObject.description,
            };
            if (paramObject.required) {
                schema.required?.push(item.key);
            }
        }
    });
    requestBody.content = {
        'application/x-www-form-urlencoded': {
            schema,
        },
    };
}
