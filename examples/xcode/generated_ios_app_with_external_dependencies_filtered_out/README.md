# Generated iOS App with external dependencies filtered out

Tuist filters out destinations cascading platform condition filters down to external dependencies. This filtering can result in external targets with no destinations, and it's important that we delete them from the graph. Otherwise the cache warming logic might try to build binaries for them, even if they are not buildable.
