import { clients } from './clients.js';

/**
 * Generate code examples for HAR requests
 */
function snippetz() {
    function findPlugin(target, client) {
        return clients.find(({ key }) => key === target)?.clients.find((plugin) => plugin.client === client);
    }
    return {
        print(target, client, request) {
            return findPlugin(target, client)?.generate(request);
        },
        clients() {
            return clients;
        },
        plugins() {
            return clients.flatMap(({ key, clients }) => clients.map((plugin) => ({
                target: key,
                client: plugin.client,
            })));
        },
        findPlugin,
        hasPlugin(target, client) {
            return Boolean(findPlugin(target, client));
        },
    };
}

export { snippetz };
