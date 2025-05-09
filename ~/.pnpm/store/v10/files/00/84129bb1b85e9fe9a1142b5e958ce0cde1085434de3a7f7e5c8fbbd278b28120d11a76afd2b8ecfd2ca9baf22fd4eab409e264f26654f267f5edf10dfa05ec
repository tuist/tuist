/** V-2.3.0 to V-2.4.0 migration */
const migrate_v_2_4_0 = (data) => {
    console.info('Performing data migration v-2.3.0 to v-2.4.0');
    const collections = Object.values(data.collections).reduce((prev, c) => {
        if (c.info?.title === 'Drafts') {
            // Remove the servers from the draft collection
            c.servers = [];
            Object.values(data.requests).forEach((request) => {
                if (request.selectedServerUid && c.requests.includes(request.uid)) {
                    const server = data.servers[request.selectedServerUid];
                    if (server) {
                        // Update the request paths to include the server URL
                        request.path = `${server.url}${request.path}`;
                    }
                    // Remove the selected server UID from the draft request
                    request.selectedServerUid = '';
                }
            });
        }
        prev[c.uid] = c;
        return prev;
    }, {});
    return {
        ...data,
        collections,
    };
};

export { migrate_v_2_4_0 };
