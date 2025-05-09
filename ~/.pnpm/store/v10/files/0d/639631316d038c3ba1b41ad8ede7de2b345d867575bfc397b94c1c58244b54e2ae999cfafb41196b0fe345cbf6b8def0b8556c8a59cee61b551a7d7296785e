import { setNestedValue, getNestedValue } from '../nested/nested.js';

/** Type safe include */
function includes(arr, x) {
    return arr.includes(x);
}
/**
 * Mutation tracker to allow history roll back/forwards
 *
 * Associates a history record with a specific data object and allows rolling back of that
 * specific object history.
 */
class Mutation {
    /** Object reference for the given data to be tracked */
    parentData;
    /** Maximum number of record to keep (how many times you can 'undo' a mutation) */
    maxRecords;
    /** List of all mutation records */
    records = [];
    /** List of side effect handlers to run whenever the data changes */
    sideEffects = [];
    /** Active mutation index. Allows rolling forward and backwards */
    idx = 0;
    /** Optional debug messages */
    debug;
    constructor(parentData, maxRecords = 5000, debug = false) {
        this.maxRecords = maxRecords;
        this.parentData = parentData;
        this.debug = debug;
    }
    /** Mutate without saving a record. Private function. */
    _unsavedMutate(path, value) {
        setNestedValue(this.parentData, path, value);
        this.runSideEffects(path);
    }
    /** Side effects must take ONLY an object of the specified type and act on it */
    addSideEffect(triggers, effect, name, immediate = true) {
        this.sideEffects.push({ triggers, effect, name });
        if (immediate) {
            effect(this.parentData);
            if (this.debug) {
                console.info(`Running mutation side effect: ${name}`, 'debug');
            }
        }
    }
    /** Runs all side effects that match the path trigger */
    runSideEffects(path) {
        this.sideEffects.forEach(({ effect, triggers, name }) => {
            const triggerEffect = triggers.some((trigger) => path.includes(trigger)) || path.length < 1;
            if (triggerEffect) {
                effect(this.parentData);
                if (this.debug) {
                    console.info(`Running mutation side effect: ${name}`, 'debug');
                }
            }
        });
    }
    /** Mutate an object with the new property value and run side effects */
    mutate(
    /** Path to nested set */
    path, 
    /** New value to set */
    value, 
    /** Optional explicit previous value. Otherwise the current value will be used */
    previousValue = null) {
        // If already rolled back then clear roll forward values before assigning new mutation
        if (this.idx < this.records.length - 1)
            this.records.splice(this.idx + 1);
        // Check for a change
        const prev = getNestedValue(this.parentData, path);
        if (prev === value)
            return;
        // Save new mutation record with previous value
        setNestedValue(this.parentData, path, value);
        this.runSideEffects(path);
        this.records.push({
            prev: previousValue ?? prev, // Optional explicit previous value
            value,
            path,
        });
        // Save new position to end
        this.idx = this.records.length - 1;
        // If the record has overflowed remove first entry
        if (this.records.length > this.maxRecords)
            this.records.shift();
        if (this.debug) {
            console.info(`Set object '${this.idx}' '${path}' to ${value}`, 'debug');
        }
    }
    /** Undo the previous mutation */
    undo() {
        if (this.idx < 0 || this.records.length < 1)
            return false;
        if (this.debug)
            console.info('Undoing Mutation', 'debug');
        const record = this.records[this.idx];
        this.idx -= 1;
        if (record)
            this._unsavedMutate(record.path, record.prev);
        return true;
    }
    /** Roll forward to the next available mutation if its exists */
    redo() {
        if (this.idx > this.records.length - 2)
            return false;
        if (this.debug)
            console.info('Redoing Mutation', 'debug');
        const record = this.records[this.idx + 1];
        this.idx += 1;
        if (record)
            this._unsavedMutate(record.path, record.value);
        return true;
    }
}

export { Mutation, includes };
