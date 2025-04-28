import { getEntrypoint } from './getEntrypoint.js';
import { makeFilesystem } from './makeFilesystem.js';
import { upgradeFromThreeToThreeOne } from './upgradeFromThreeToThreeOne.js';
import { upgradeFromTwoToThree } from './upgradeFromTwoToThree.js';

/**
 * Upgrade specification to OpenAPI 3.1.0
 */
function upgrade(value) {
    if (!value) {
        return {
            specification: null,
            version: '3.1',
        };
    }
    const upgraders = [upgradeFromTwoToThree, upgradeFromThreeToThreeOne];
    // TODO: Run upgrade over the whole filesystem
    const result = upgraders.reduce((currentSpecification, upgrader) => upgrader(currentSpecification), getEntrypoint(makeFilesystem(value)).specification);
    return {
        specification: result,
        // TODO: Make dynamic
        version: '3.1',
    };
}

export { upgrade };
