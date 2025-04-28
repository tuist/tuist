import { getListOfReferences } from './getListOfReferences.js';
import { isFilesystem } from './isFilesystem.js';
import { normalize } from './normalize.js';

function makeFilesystem(value, overwrites = {}) {
    // Keep as is
    if (isFilesystem(value)) {
        return value;
    }
    // Make an object
    const specification = normalize(value);
    // Create fake filesystem
    return [
        {
            isEntrypoint: true,
            specification,
            filename: null,
            dir: './',
            references: getListOfReferences(specification),
            ...overwrites,
        },
    ];
}

export { makeFilesystem };
