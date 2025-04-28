import { getEntrypoint } from './getEntrypoint.js';
import { makeFilesystem } from './makeFilesystem.js';
import { traverse } from './traverse.js';

/**
 * Filter the specification based on the callback
 */
function filter(specification, callback) {
    const filesystem = makeFilesystem(specification);
    return {
        specification: traverse(getEntrypoint(filesystem).specification, (schema) => {
            return callback(schema) ? schema : undefined;
        }),
    };
}

export { filter };
