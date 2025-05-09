import { getEntrypoint } from '../../getEntrypoint.js';
import { toJson as toJson$1 } from '../../toJson.js';
import { workThroughQueue } from '../utils/workThroughQueue.js';

/**
 * Run the chained tasks and return the results
 */
async function toJson(queue) {
    const { filesystem } = await workThroughQueue(queue);
    return toJson$1(getEntrypoint(filesystem).specification);
}

export { toJson };
