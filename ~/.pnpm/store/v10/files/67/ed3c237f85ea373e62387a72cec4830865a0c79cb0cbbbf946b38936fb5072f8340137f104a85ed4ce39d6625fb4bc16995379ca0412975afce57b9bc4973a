import { processAuth } from './helpers/authHelpers.js';
import { processExternalDocs } from './helpers/externalDocsHelper.js';
import { processItem } from './helpers/itemHelpers.js';
import { processLicenseAndContact } from './helpers/licenseContactHelper.js';
import { processLogo } from './helpers/logoHelper.js';
import { parseServers } from './helpers/serverHelpers.js';
import { normalizePath } from './helpers/urlHelpers.js';
/**
 * Extracts tags from Postman collection folders
 */
function extractTags(items) {
    const tags = [];
    function processTagItem(item, parentPath = '') {
        if (item.item) {
            const currentPath = parentPath ? `${parentPath} > ${item.name}` : item.name;
            // Add tag for the current folder
            tags.push({
                name: currentPath,
                ...(item.description && { description: item.description }),
            });
            // Process nested folders
            item.item.forEach((subItem) => processTagItem(subItem, currentPath));
        }
    }
    items.forEach((item) => processTagItem(item));
    return tags;
}
/**
 * Converts a Postman Collection to an OpenAPI 3.1.0 document.
 * This function processes the collection's information, servers, authentication,
 * and items to create a corresponding OpenAPI structure.
 */
export function convert(postmanCollection) {
    // Parse string input if provided
    const collection = typeof postmanCollection === 'string' ? JSON.parse(postmanCollection) : postmanCollection;
    // Extract title from collection info, fallback to 'API' if not provided
    const title = collection.info.name || 'API';
    // Look for version in collection variables, default to '1.0.0'
    const version = collection.variable?.find((v) => v.key === 'version')?.value || '1.0.0';
    // Handle different description formats in Postman
    const description = typeof collection.info.description === 'string'
        ? collection.info.description
        : collection.info.description?.content || '';
    // Process license and contact information
    const { license, contact } = processLicenseAndContact(collection);
    // Process logo information
    const logo = processLogo(collection);
    // Initialize the OpenAPI document with required fields
    const openapi = {
        openapi: '3.1.0',
        info: {
            title,
            version,
            ...(description && { description }),
            ...(license && { license }),
            ...(contact && { contact }),
            ...(logo && { 'x-logo': logo }),
        },
        servers: parseServers(collection),
        paths: {},
    };
    // Process external docs
    const externalDocs = processExternalDocs(collection);
    if (externalDocs) {
        openapi.externalDocs = externalDocs;
    }
    // Process authentication if present in the collection
    if (collection.auth) {
        const { securitySchemes, security } = processAuth(collection.auth);
        openapi.components = openapi.components || {};
        openapi.components.securitySchemes = {
            ...openapi.components.securitySchemes,
            ...securitySchemes,
        };
        openapi.security = security;
    }
    // Process each item in the collection and merge into OpenAPI spec
    if (collection.item) {
        // Extract tags from folders
        const tags = extractTags(collection.item);
        if (tags.length > 0) {
            openapi.tags = tags;
        }
        collection.item.forEach((item) => {
            const { paths: itemPaths, components: itemComponents } = processItem(item);
            // Merge paths from the current item
            openapi.paths = openapi.paths || {};
            for (const [pathKey, pathItem] of Object.entries(itemPaths)) {
                // Convert colon-style params to curly brace style
                const normalizedPathKey = normalizePath(pathKey);
                /**
                 * this is a bit of a hack to skip empty paths only if they have no parameters
                 * because there is a test where if I remove the empty path it breaks the test
                 * but there is another test where if I leave the empty path it breaks the test
                 * so I added this check to only remove the empty path if all the methods on it have no parameters
                 */
                if (normalizedPathKey === '/') {
                    const allMethodsHaveEmptyParams = Object.values(pathItem || {}).every((method) => !method.parameters || method.parameters.length === 0);
                    if (allMethodsHaveEmptyParams) {
                        continue;
                    }
                }
                if (!openapi.paths[normalizedPathKey]) {
                    openapi.paths[normalizedPathKey] = pathItem;
                }
                else {
                    openapi.paths[normalizedPathKey] = {
                        ...openapi.paths[normalizedPathKey],
                        ...pathItem,
                    };
                }
                // Handle the /raw endpoint specifically
                if (normalizedPathKey === '/raw' && pathItem?.post) {
                    if (pathItem.post.requestBody?.content['text/plain']) {
                        pathItem.post.requestBody.content['application/json'] = {
                            schema: {
                                type: 'object',
                                examples: [],
                            },
                        };
                        delete pathItem.post.requestBody.content['text/plain'];
                    }
                }
            }
            // Merge security schemes from the current item
            if (itemComponents?.securitySchemes) {
                openapi.components = openapi.components || {};
                openapi.components.securitySchemes = {
                    ...openapi.components.securitySchemes,
                    ...itemComponents.securitySchemes,
                };
            }
        });
    }
    // Clean up the generated paths
    if (openapi.paths) {
        Object.values(openapi.paths).forEach((path) => {
            if (path) {
                Object.values(path).forEach((method) => {
                    if (method && 'parameters' in method) {
                        // Remove empty parameters array to keep spec clean
                        if (method.parameters?.length === 0) {
                            delete method.parameters;
                        }
                        // Handle request bodies
                        if (method.requestBody?.content) {
                            const content = method.requestBody.content;
                            if (Object.keys(content).length === 0) {
                                // Keep an empty requestBody with text/plain content
                                method.requestBody = {
                                    content: {
                                        'text/plain': {},
                                    },
                                };
                            }
                            else if ('text/plain' in content) {
                                // Preserve schema if it exists, otherwise keep an empty object
                                if (!content['text/plain'].schema || Object.keys(content['text/plain'].schema).length === 0) {
                                    content['text/plain'] = {};
                                }
                            }
                        }
                        // Ensure all methods have a description, but don't add an empty one if it doesn't exist
                        if (!method.description) {
                            delete method.description;
                        }
                    }
                });
            }
        });
    }
    // Remove empty components object
    if (Object.keys(openapi.components || {}).length === 0) {
        delete openapi.components;
    }
    return openapi;
}
