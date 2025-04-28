import { details as details$1 } from '../../details.js';
import { getEntrypoint } from '../../getEntrypoint.js';
import { workThroughQueue } from '../utils/workThroughQueue.js';

/**
 * Run the chained tasks and return just some basic information about the OpenAPI document
 */
async function details(queue) {
    const { filesystem } = await workThroughQueue(queue);
    return details$1(getEntrypoint(filesystem).specification);
}

export { details };
