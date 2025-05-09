import type { OpenAPI } from '@scalar/openapi-types';
import type { AnyObject, ErrorObject, Filesystem, FilesystemEntry, ThrowOnErrorOption } from '../types/index.ts';
export type ResolveReferencesResult = {
    valid: boolean;
    errors: ErrorObject[];
    schema: OpenAPI.Document;
};
export type ResolveReferencesOptions = ThrowOnErrorOption & {
    /**
     * Fired when dereferenced a schema.
     *
     * Note that for object schemas, its properties may not be dereferenced when the hook is called.
     */
    onDereference?: (data: {
        schema: AnyObject;
        ref: string;
    }) => void;
};
/**
 * Takes a specification and resolves all references.
 */
export declare function resolveReferences(input: AnyObject | Filesystem, options?: ResolveReferencesOptions, file?: FilesystemEntry, errors?: ErrorObject[]): ResolveReferencesResult;
//# sourceMappingURL=resolveReferences.d.ts.map