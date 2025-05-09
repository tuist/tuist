import { Mutation } from './mutations.js';
import { stringify } from 'flatted';
import { debounce } from './debounce.js';
import { LS_CONFIG } from './local-storage.js';

const MAX_MUTATION_RECORDS = 500;
/** Generate mutation handlers for a given record of objects  */
function mutationFactory(entityMap, mutationMap, localStorageKey, maxNumberRecords = MAX_MUTATION_RECORDS) {
    function getMutator(uid) {
        const mutator = mutationMap[uid];
        if (!mutator)
            console.warn(`Missing ${entityMap[uid] ? 'mutator' : 'object'} for uid: ${uid}`);
        return mutator ?? null;
    }
    /** Triggers on any changes so we can save to localStorage */
    const onChange = localStorageKey
        ? debounce(() => localStorage.setItem(localStorageKey, stringify(entityMap)), LS_CONFIG.DEBOUNCE_MS, {
            maxWait: LS_CONFIG.MAX_WAIT_MS,
        })
        : () => null;
    /** Adds a new item to the record of tracked items and creates a new mutation tracking instance */
    const add = (item) => {
        entityMap[item.uid] = item;
        mutationMap[item.uid] = new Mutation(item, maxNumberRecords);
        onChange();
    };
    return {
        /** Adds a new item to the record of tracked items and creates a new mutation tracking instance */
        add,
        delete: (uid) => {
            delete entityMap[uid];
            delete mutationMap[uid];
            onChange();
        },
        /** Destructive, overwrites a record to a new item and creates a new mutation tracking instance */
        set: (item) => {
            entityMap[item.uid] = item;
            mutationMap[item.uid] = new Mutation(item, maxNumberRecords);
            onChange();
        },
        /** Update a nested property and track the mutation */
        edit: (uid, path, value) => {
            const mutator = getMutator(uid);
            mutator?.mutate(path, value);
            onChange();
        },
        /** Commit an untracked edit to the object (undo/redo will not work) */
        untrackedEdit: (uid, path, value) => {
            const mutator = getMutator(uid);
            mutator?._unsavedMutate(path, value);
            onChange();
        },
        /** Undo the last mutation */
        undo: (uid) => {
            const mutator = getMutator(uid);
            mutator?.undo();
            onChange();
        },
        /** Redo a mutation if available */
        redo: (uid) => {
            const mutator = getMutator(uid);
            mutator?.redo();
            onChange();
        },
        /** Destructive, clears the record */
        reset: () => {
            Object.keys(entityMap).forEach((uid) => {
                delete entityMap[uid];
                delete mutationMap[uid];
            });
            onChange();
        },
    };
}

export { mutationFactory };
