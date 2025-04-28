import { details } from '../actions/details.js';
import { files } from '../actions/files.js';
import { get } from '../actions/get.js';
import { toJson } from '../actions/toJson.js';
import { toYaml } from '../actions/toYaml.js';
import { queueTask } from '../utils/queueTask.js';
import { dereferenceCommand } from './dereferenceCommand.js';
import { filterCommand } from './filterCommand.js';
import { upgradeCommand } from './upgradeCommand.js';
import { validateCommand } from './validateCommand.js';

/**
 * Pass any OpenAPI document
 */
function loadCommand(previousQueue, input, options) {
    const task = {
        name: 'load',
        options: {
            // global
            throwOnError: previousQueue.options?.throwOnError,
            // local
            ...options,
        },
    };
    const queue = {
        // Add the load task
        ...queueTask(previousQueue, task),
        // Add input to the queue
        input,
    };
    return {
        dereference: (dereferenceOptions) => dereferenceCommand(queue, dereferenceOptions),
        details: () => details(queue),
        files: () => files(queue),
        filter: (callback) => filterCommand(queue, callback),
        get: () => get(queue),
        upgrade: () => upgradeCommand(queue),
        toJson: () => toJson(queue),
        toYaml: () => toYaml(queue),
        validate: (validateOptions) => validateCommand(queue, validateOptions),
    };
}

export { loadCommand };
