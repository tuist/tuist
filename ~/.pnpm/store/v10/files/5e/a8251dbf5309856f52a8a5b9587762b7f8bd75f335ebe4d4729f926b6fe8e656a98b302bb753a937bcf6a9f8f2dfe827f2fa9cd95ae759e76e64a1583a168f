import { Validator } from '../lib/Validator/Validator.js';
import { makeFilesystem } from './makeFilesystem.js';

/**
 * Validates an OpenAPI document
 */
async function validate(value, options) {
    const filesystem = makeFilesystem(value);
    const validator = new Validator();
    const result = await validator.validate(filesystem, options);
    return {
        ...result,
        specification: validator.specification,
        version: validator.version,
    };
}

export { validate };
