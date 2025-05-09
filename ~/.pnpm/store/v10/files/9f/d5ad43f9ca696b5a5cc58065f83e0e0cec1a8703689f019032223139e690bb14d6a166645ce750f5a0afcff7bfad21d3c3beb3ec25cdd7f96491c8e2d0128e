import { details } from '../actions/details.js';
import { files } from '../actions/files.js';
import { get } from '../actions/get.js';
import { toJson } from '../actions/toJson.js';
import { toYaml } from '../actions/toYaml.js';
import { queueTask } from '../utils/queueTask.js';
import { dereferenceCommand } from './dereferenceCommand.js';

/**
 * Filter the given OpenAPI document
 */
function filterCommand(previousQueue, options) {
    const task = {
        name: 'filter',
        options,
    };
    const queue = queueTask(previousQueue, task);
    return {
        dereference: (dereferenceOptions) => dereferenceCommand(queue, dereferenceOptions),
        details: () => details(queue),
        files: () => files(queue),
        get: () => get(queue),
        toJson: () => toJson(queue),
        toYaml: () => toYaml(queue),
    };
}

export { filterCommand };
