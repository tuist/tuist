import { type Path, type PathValue } from '../nested/index.js';
/** Type safe include */
export declare function includes<T>(arr: readonly T[], x: T): boolean;
/** Nested paths of the data type */
type MutationPath<D> = Path<D>;
/** Mutation record for a specific value and data type */
type MutationRecord<T, D> = {
    prev: T;
    value: T;
    path: MutationPath<D>;
};
/** Mutation effect function that is run provisioned with the data object */
type MutationEffect<T> = (data: T) => void;
/** Effect record that holds the possible change trigger keys for the effect to run */
type MutationEffectRecord<T> = {
    /** Side effect name for debug logs */
    name: string;
    /**
     * List of path keys to run effect for. Any nested changes will also trigger the side effect
     * ex. 'foo.bar'
     */
    triggers: string[];
    /**
     * Side effect function to run. A copy of the updated data value is passed to the handler
     */
    effect: MutationEffect<T>;
};
/**
 * Mutation tracker to allow history roll back/forwards
 *
 * Associates a history record with a specific data object and allows rolling back of that
 * specific object history.
 */
export declare class Mutation<DataType> {
    /** Object reference for the given data to be tracked */
    parentData: DataType;
    /** Maximum number of record to keep (how many times you can 'undo' a mutation) */
    maxRecords: number;
    /** List of all mutation records */
    records: MutationRecord<any, DataType>[];
    /** List of side effect handlers to run whenever the data changes */
    sideEffects: MutationEffectRecord<DataType>[];
    /** Active mutation index. Allows rolling forward and backwards */
    idx: number;
    /** Optional debug messages */
    debug: boolean;
    constructor(parentData: DataType, maxRecords?: number, debug?: boolean);
    /** Mutate without saving a record. Private function. */
    _unsavedMutate<K extends MutationPath<DataType>>(path: K, value: PathValue<DataType, K>): void;
    /** Side effects must take ONLY an object of the specified type and act on it */
    addSideEffect(triggers: string[], effect: MutationEffect<DataType>, name: string, immediate?: boolean): void;
    /** Runs all side effects that match the path trigger */
    runSideEffects(path: MutationPath<DataType>): void;
    /** Mutate an object with the new property value and run side effects */
    mutate<K extends MutationPath<DataType>>(
    /** Path to nested set */
    path: K, 
    /** New value to set */
    value: PathValue<DataType, K>, 
    /** Optional explicit previous value. Otherwise the current value will be used */
    previousValue?: PathValue<DataType, K> | null): void;
    /** Undo the previous mutation */
    undo(): boolean;
    /** Roll forward to the next available mutation if its exists */
    redo(): boolean;
}
export {};
//# sourceMappingURL=mutations.d.ts.map