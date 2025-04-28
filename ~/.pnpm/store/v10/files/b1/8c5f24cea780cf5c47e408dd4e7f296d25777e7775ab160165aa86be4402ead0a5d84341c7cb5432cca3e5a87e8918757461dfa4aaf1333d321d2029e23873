import { details } from '../actions/details.js';
import { files } from '../actions/files.js';
import { get } from '../actions/get.js';
import { toJson } from '../actions/toJson.js';
import { toYaml } from '../actions/toYaml.js';
import { queueTask } from '../utils/queueTask.js';

/**
 * Dereference the given OpenAPI document
 */
function dereferenceCommand(previousQueue, options) {
    const task = {
        name: 'dereference',
        options: {
            throwOnError: previousQueue.options?.throwOnError,
            ...(options ?? {}),
        },
    };
    const queue = queueTask(previousQueue, task);
    return {
        details: () => details(queue),
        files: () => files(queue),
        get: () => get(queue),
        toJson: () => toJson(queue),
        toYaml: () => toYaml(queue),
    };
}

export { dereferenceCommand };
