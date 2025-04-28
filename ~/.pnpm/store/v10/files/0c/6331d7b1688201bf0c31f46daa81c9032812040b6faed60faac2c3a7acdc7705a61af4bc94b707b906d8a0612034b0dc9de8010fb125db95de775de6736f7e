import prettify from './helpers.js';

function betterAjvErrors(schema, data, errors, options = {}) {
    const { indent = null, json = null } = options;
    const jsonRaw = json || JSON.stringify(data, null, indent);
    const customErrorToStructure = (error) => error.getError();
    const customErrors = prettify(errors, {
        data,
        schema,
        jsonRaw,
    });
    return customErrors.map(customErrorToStructure);
}

export { betterAjvErrors };
