import { OpenApiVersions } from '../configuration/index.js';

/**
 * Get versions of the OpenAPI document.
 */
function details(specification) {
    if (specification === null) {
        return {
            version: undefined,
            specificationType: undefined,
            specificationVersion: undefined,
        };
    }
    for (const version of new Set(OpenApiVersions)) {
        const specificationType = version === '2.0' ? 'swagger' : 'openapi';
        const value = specification[specificationType];
        if (typeof value === 'string' && value.startsWith(version)) {
            return {
                version: version,
                specificationType,
                specificationVersion: value,
            };
        }
    }
    return {
        version: undefined,
        specificationType: undefined,
        specificationVersion: undefined,
    };
}

export { details };
