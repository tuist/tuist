import { details } from '../actions/details.js';
import { files } from '../actions/files.js';
import { get } from '../actions/get.js';
import { toJson } from '../actions/toJson.js';
import { toYaml } from '../actions/toYaml.js';
import { queueTask } from '../utils/queueTask.js';
import { dereferenceCommand } from './dereferenceCommand.js';
import { filterCommand } from './filterCommand.js';
import { upgradeCommand } from './upgradeCommand.js';

/**
 * Validate the given OpenAPI document
 */
function validateCommand(previousQueue, options) {
    const task = {
        name: 'validate',
        options: {
            throwOnError: previousQueue.options?.throwOnError,
            ...(options ?? {}),
        },
    };
    const queue = queueTask(previousQueue, task);
    return {
        dereference: (dereferenceOptions) => dereferenceCommand(queue, dereferenceOptions),
        details: () => details(queue),
        files: () => files(queue),
        filter: (callback) => filterCommand(queue, callback),
        get: () => get(queue),
        toJson: () => toJson(queue),
        toYaml: () => toYaml(queue),
        upgrade: () => upgradeCommand(queue),
    };
}

export { validateCommand };
