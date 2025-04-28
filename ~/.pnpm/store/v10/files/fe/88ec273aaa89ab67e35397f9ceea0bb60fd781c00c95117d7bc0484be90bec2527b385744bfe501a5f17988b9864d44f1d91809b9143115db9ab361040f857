import { getEntrypoint } from '../../getEntrypoint.js';
import { toYaml as toYaml$1 } from '../../toYaml.js';
import { workThroughQueue } from '../utils/workThroughQueue.js';

/**
 * Run the chained tasks and return the results
 */
async function toYaml(queue) {
    const { filesystem } = await workThroughQueue(queue);
    return toYaml$1(getEntrypoint(filesystem).specification);
}

export { toYaml };
