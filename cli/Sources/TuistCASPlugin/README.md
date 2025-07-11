# TuistCASPlugin

A Swift implementation of Apple's CAS (Content Addressable Storage) plugin interface that integrates with Tuist server.

## Overview

This plugin allows the Swift build system to use Tuist server as a content-addressable store for build caching. It implements the C API interface expected by the Swift build system.

## Building

Build the dynamic library using Swift Package Manager:

```bash
swift build -c release --product TuistCASPlugin
```

This will create a dynamic library (`.dylib`) that can be loaded by the Swift build system.

## Configuration

To use this plugin with the Swift build system, set these build settings:

```bash
export COMPILATION_CACHE_ENABLE_PLUGIN=YES
export COMPILATION_CACHE_PLUGIN_PATH=/path/to/TuistCASPlugin.dylib
export COMPILATION_CACHE_REMOTE_SERVICE_PATH=/path/to/tuist-server
```

You can also configure the plugin options:

- `server_url`: URL of the Tuist server (default: https://cloud.tuist.io)
- `auth_token`: Authentication token for the server
- `project_id`: Project identifier

## API Implementation

The plugin implements the following C API functions required by the Swift build system:

### Core Functions
- `llcas_get_plugin_version`: Returns plugin version
- `llcas_cas_create`: Creates a CAS instance
- `llcas_cas_store_object`: Stores objects by content hash
- `llcas_cas_load_object`: Loads objects by ID

### Action Cache Functions
- `llcas_actioncache_put_for_digest_async`: Caches build results
- `llcas_actioncache_get_for_digest_async`: Retrieves cached results

### Memory Management
- `llcas_string_dispose`: Deallocates C strings
- `llcas_cas_dispose`: Cleans up CAS instances

## Integration with Tuist Server

The plugin communicates with the Tuist server via HTTP/REST APIs to:

1. **Store build artifacts**: Upload compiled objects and their metadata
2. **Retrieve cached results**: Download previously built artifacts
3. **Cache build actions**: Store mapping from build keys to result artifacts
4. **Query cache**: Check if a build result is already available

## Error Handling

The plugin handles various error conditions:

- Network connectivity issues
- Authentication failures
- Server-side errors
- Invalid object references
- Memory allocation failures

All errors are properly propagated to the Swift build system with descriptive error messages.

## Thread Safety

The implementation is thread-safe and supports:

- Concurrent object storage and retrieval
- Asynchronous operations with cancellation support
- Proper memory management across threads

## Future Enhancements

Potential improvements include:

- Local disk caching for better performance
- Compression of stored objects
- Incremental uploads for large artifacts
- Health monitoring and metrics
- Advanced authentication schemes