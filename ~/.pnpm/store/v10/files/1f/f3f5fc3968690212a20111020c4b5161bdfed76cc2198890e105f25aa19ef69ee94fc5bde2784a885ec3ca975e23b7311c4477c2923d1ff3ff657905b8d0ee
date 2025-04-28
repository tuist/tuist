import { workThroughQueue } from '../utils/workThroughQueue.js';

/**
 * Run the chained tasks and return the results
 */
async function get(queue) {
    return {
        filesystem: [],
        ...(await workThroughQueue(queue)),
    };
}

export { get };
