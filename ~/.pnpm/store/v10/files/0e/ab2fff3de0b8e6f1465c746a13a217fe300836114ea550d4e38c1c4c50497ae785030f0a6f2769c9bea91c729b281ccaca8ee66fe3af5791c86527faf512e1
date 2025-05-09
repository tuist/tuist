import Swagger20 from '../schemas/v2.0/schema.json.js';
import OpenApi30 from '../schemas/v3.0/schema.json.js';
import OpenApi31 from '../schemas/v3.1/schema.json.js';

/**
 * A list of the supported OpenAPI specifications
 */
const OpenApiSpecifications = {
    '2.0': Swagger20,
    '3.0': OpenApi30,
    '3.1': OpenApi31,
};
const OpenApiVersions = Object.keys(OpenApiSpecifications);
/**
 * List of error messages used in the Validator
 */
const ERRORS = {
    EMPTY_OR_INVALID: 'Can’t find JSON, YAML or filename in data',
    // URI_MUST_BE_STRING: 'uri parameter or $id attribute must be a string',
    OPENAPI_VERSION_NOT_SUPPORTED: 'Can’t find supported Swagger/OpenAPI version in specification, version must be a string.',
    INVALID_REFERENCE: 'Can’t resolve reference: %s',
    EXTERNAL_REFERENCE_NOT_FOUND: 'Can’t resolve external reference: %s',
    FILE_DOES_NOT_EXIST: 'File does not exist: %s',
    NO_CONTENT: 'No content found',
};

export { ERRORS, OpenApiSpecifications, OpenApiVersions };
