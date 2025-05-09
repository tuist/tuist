import type { OpenAPI } from '@scalar/openapi-types';
/**
 * Pass an array of strings to get a valid OpenAPI pointer.
 *
 * Works with any path, but is typed to allow the paths that we support.
 *
 * @example
 * ['paths', '/planets/{foo}', 'get'] > '#/paths/~1planets~1{foo}/get'
 * ['components', 'schemas', 'Planet] > '#/components/schemas/Planet'
 */
type ValidOpenApiPaths = ['paths', string, Lowercase<OpenAPI.HttpMethod> | string] | ['components', 'schemas', string];
/**
 * Encodes a location string with paths
 *
 * @example
 * getPointer(['paths', '/planets/{foo}', 'get'])
 *
 * '#/paths/~1planets~1{foo}/get'
 */
export declare function getPointer(path: ValidOpenApiPaths): `#/${string}`;
export {};
//# sourceMappingURL=getPointer.d.ts.map