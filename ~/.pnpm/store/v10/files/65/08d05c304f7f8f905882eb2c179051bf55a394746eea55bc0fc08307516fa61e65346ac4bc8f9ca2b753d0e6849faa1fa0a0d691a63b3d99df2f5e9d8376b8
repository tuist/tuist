import { Mutation } from '../mutator-record/mutations.js';
import type { Path, PathValue } from '../nested/index.js';
/** Generate mutation handlers for a given record of objects  */
export declare function mutationFactory<T extends Record<string, any> & {
    uid: string;
}>(entityMap: Partial<Record<string, T>>, mutationMap: Partial<Record<string, Mutation<T>>>, localStorageKey?: string | false, maxNumberRecords?: number): {
    /** Adds a new item to the record of tracked items and creates a new mutation tracking instance */
    add: (item: T) => void;
    delete: (uid: string) => void;
    /** Destructive, overwrites a record to a new item and creates a new mutation tracking instance */
    set: (item: T) => void;
    /** Update a nested property and track the mutation */
    edit: <P extends Path<T>>(uid: string, path: P, value: PathValue<T, P>) => void;
    /** Commit an untracked edit to the object (undo/redo will not work) */
    untrackedEdit: <P extends Path<T>>(uid: string, path: P, value: PathValue<T, P>) => void;
    /** Undo the last mutation */
    undo: (uid: string) => void;
    /** Redo a mutation if available */
    redo: (uid: string) => void;
    /** Destructive, clears the record */
    reset: () => void;
};
export type Mutators<T extends object & {
    uid: string;
}> = ReturnType<typeof mutationFactory<T>>;
//# sourceMappingURL=handlers.d.ts.map