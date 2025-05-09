import { details } from './details.js';
import { getEntrypoint } from './getEntrypoint.js';
import { makeFilesystem } from './makeFilesystem.js';
import { resolveReferences } from './resolveReferences.js';

/**
 * Resolves all references in an OpenAPI document
 */
async function dereference(value, options) {
    const filesystem = makeFilesystem(value);
    const entrypoint = getEntrypoint(filesystem);
    const result = resolveReferences(filesystem, options);
    return {
        specification: entrypoint.specification,
        errors: result.errors,
        schema: result.schema,
        ...details(entrypoint.specification),
    };
}

export { dereference };
