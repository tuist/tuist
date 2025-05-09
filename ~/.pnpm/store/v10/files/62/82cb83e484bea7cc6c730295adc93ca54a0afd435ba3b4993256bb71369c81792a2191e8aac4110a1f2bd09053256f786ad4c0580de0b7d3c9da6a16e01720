import { addInfoObject } from './utils/addInfoObject.js';
export { DEFAULT_TITLE, DEFAULT_VERSION } from './utils/addInfoObject.js';
import { addLatestOpenApiVersion } from './utils/addLatestOpenApiVersion.js';
export { DEFAULT_OPENAPI_VERSION } from './utils/addLatestOpenApiVersion.js';
import { addMissingTags } from './utils/addMissingTags.js';
import { normalizeSecuritySchemes } from './utils/normalizeSecuritySchemes.js';
import { rejectSwaggerDocuments } from './utils/rejectSwaggerDocuments.js';

/**
 * Make an OpenAPI document a valid and clean OpenAPI document
 */
function sanitize(definition) {
    const transformers = [
        rejectSwaggerDocuments,
        addLatestOpenApiVersion,
        addInfoObject,
        addMissingTags,
        normalizeSecuritySchemes,
    ];
    return transformers.reduce((doc, transformer) => transformer(doc), definition);
}

export { sanitize };
