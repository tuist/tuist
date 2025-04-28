import { betterAjvErrors } from './betterAjvErrors/index.js';

/**
 * Transforms ajv errors, finds the positions in the schema and returns an enriched format.
 */
function transformErrors(specification, errors) {
    // TODO: This should work with multiple files
    if (typeof errors === 'string') {
        return [
            {
                message: errors,
            },
        ];
    }
    return betterAjvErrors(specification, null, errors, {
        indent: 2,
    }).map((error) => {
        error.message = error.message.trim();
        return error;
    });
}

export { transformErrors };
