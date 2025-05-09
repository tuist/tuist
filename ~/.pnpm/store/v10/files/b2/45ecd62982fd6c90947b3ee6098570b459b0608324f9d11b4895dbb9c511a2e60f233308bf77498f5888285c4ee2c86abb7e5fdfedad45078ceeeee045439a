import { normalizeMimeType } from './normalizeMimeType.js';

/**
 * Remove charset from content types
 *
 * Example: `application/json; charset=utf-8` -> `application/json`
 */
function normalizeMimeTypeObject(content) {
    if (!content) {
        return content;
    }
    // Clone the object
    const newContent = {
        ...content,
    };
    Object.keys(newContent).forEach((key) => {
        // Input: 'application/problem+json; charset=utf-8'
        // Output: 'application/json'
        const newKey = normalizeMimeType(key);
        // We need a new key to replace the old one
        if (newKey === undefined) {
            return;
        }
        // Move the content
        newContent[newKey] = newContent[key];
        // Remove the old key
        if (key !== newKey) {
            delete newContent[key];
        }
    });
    return newContent;
}

export { normalizeMimeTypeObject };
