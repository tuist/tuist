import { loadCommand } from './commands/loadCommand.js';

/**
 * Creates a fluent OpenAPI pipeline
 */
function openapi(globalOptions) {
    // Create a new queue
    const queue = {
        input: null,
        options: globalOptions,
        tasks: [],
    };
    return {
        load: (input, options) => loadCommand(queue, input, options),
    };
}

export { openapi };
