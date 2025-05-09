import type { WorkspaceStore } from '../../../store';
import type { ActiveEntitiesStore } from '../../../store/active-entities';
import { type Path, type PathValue } from '@scalar/object-utils/nested';
import { type Difference } from 'microdiff';
import { type ZodSchema, type ZodTypeDef } from 'zod';
/**
 * Combine Rename Diffs
 * Rename diffs show up as a delete and an add.
 * This will go through the diff and combine any diff items which are next to each other which go from remove to add.
 *
 * - first we check if the payloads are the same then it was just a simple rename
 * - next we will add the rename and also handle any changes in the diff
 */
export declare const combineRenameDiffs: (diff: Difference[], pathPrefix?: string[]) => Difference[];
/** Like array.find but returns the resource instead of the uid */
export declare const findResource: <T>(arr: string[], resources: Record<string, T>, condition: (resource: T) => boolean) => T | null;
/**
 * Traverses a zod schema based on the path and returns the schema at the end of the path
 * or null if the path doesn't exist. Handles optional unwrapping, records, and arrays
 */
export declare const traverseZodSchema: (schema: ZodSchema, path: (string | number)[]) => ZodSchema | null;
/**
 * Takes in diff, uses the path to get to the nested schema then parse the value
 * If there is a sub schema and it successfully parses, both the path and new value are valid and returned as such
 *
 * We return a tuple to make it easier to pass into the mutators
 */
export declare const parseDiff: <T>(schema: ZodSchema<T, ZodTypeDef, any>, diff: Difference) => {
    /** Typed path as it has been checked agains the schema */
    path: Path<T>;
    /** Path without the last item, used for getting the whole array instead of an item of the array */
    pathMinusOne: Path<T>;
    /** Typed value which has been parsed against the schema */
    value: PathValue<T, Path<T>> | undefined;
} | null;
/**
 * Transforms the diff into a payload for the collection mutator then executes that mutation
 *
 * @returns true if it succeeds, and false for a failure
 */
export declare const mutateCollectionDiff: (diff: Difference, { activeCollection }: ActiveEntitiesStore, { collectionMutators }: WorkspaceStore) => boolean;
/**
 * Generates an array of payloads for the request mutator from the request diff, also executes the mutation
 */
export declare const mutateRequestDiff: (diff: Difference, { activeCollection }: ActiveEntitiesStore, store: WorkspaceStore) => boolean;
/** Generates a payload for the server mutator from the server diff including the mutator method */
export declare const mutateServerDiff: (diff: Difference, { activeCollection }: ActiveEntitiesStore, { servers, serverMutators }: WorkspaceStore) => boolean;
/** Generates a payload for the tag mutator from the tag diff */
export declare const mutateTagDiff: (diff: Difference, { activeCollection }: ActiveEntitiesStore, { tags, tagMutators }: WorkspaceStore) => boolean;
/** Narrows down a zod union schema */
export declare const narrowUnionSchema: (schema: ZodSchema, key: string, value: string) => ZodSchema | null;
/**
 * Generates a payload for the security scheme mutator from the security scheme diff, then executes that mutation
 *
 * Note: for edit we cannot use parseDiff here as it can't do unions, so we handle the unions first
 *
 * @returns true if it succeeds, and false for a failure
 */
export declare const mutateSecuritySchemeDiff: (diff: Difference, { activeCollection }: ActiveEntitiesStore, { securitySchemes, securitySchemeMutators }: WorkspaceStore) => boolean;
//# sourceMappingURL=watch-mode.d.ts.map