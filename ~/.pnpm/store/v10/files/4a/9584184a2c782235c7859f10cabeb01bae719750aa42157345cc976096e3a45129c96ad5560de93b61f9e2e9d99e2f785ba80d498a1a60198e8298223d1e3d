import { unescapeJsonPointer } from './unescapeJsonPointer.js';

/**
 * Translate `/paths/~1test` to `['paths', '/test']`
 */
function getSegmentsFromPath(path) {
    return (
    // /paths/~1test
    path
        // ['', 'paths', '~1test']
        .split('/')
        // ['paths', '~test']
        .slice(1)
        // ['paths', '/test']
        .map(unescapeJsonPointer));
}

export { getSegmentsFromPath };
