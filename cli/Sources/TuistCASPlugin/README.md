# TuistCASPlugin

A Swift implementation of Apple's CAS (Content Addressable Storage) plugin interface that integrates with Tuist server.

## Overview

This plugin allows the Swift build system to use Tuist server as a content-addressable store for build caching. It implements the C API interface expected by the Swift build system, following the specification from Apple's [swift-build repository](https://github.com/swiftlang/swift-build).

The plugin exports 31 C API functions as a dynamic library that can be loaded by swift-build to provide distributed caching capabilities.

## Building

Build the dynamic library using Swift Package Manager:

```bash
# Development build
swift build --product TuistCASPlugin

# Release build (recommended for production)
swift build -c release --product TuistCASPlugin
```

This will create a dynamic library (`libTuistCASPlugin.dylib`) in `.build/{architecture}/debug/` or `.build/{architecture}/release/` that can be loaded by the Swift build system.

You can also build using Tuist's Xcode project:

```bash
tuist generate --no-open
xcodebuild build -workspace Tuist.xcworkspace -scheme TuistCASPlugin
```

## Configuration

To use this plugin with the Swift build system, set these build settings:

```bash
export COMPILATION_CACHE_ENABLE_PLUGIN=YES
export COMPILATION_CACHE_PLUGIN_PATH=/path/to/libTuistCASPlugin.dylib
export COMPILATION_CACHE_REMOTE_SERVICE_PATH=https://tuist.dev
```

For example, if you built with Swift Package Manager:

```bash
export COMPILATION_CACHE_PLUGIN_PATH=$(pwd)/.build/arm64-apple-macosx/release/libTuistCASPlugin.dylib
```

You can also configure the plugin options:

- `server_url`: URL of the Tuist server (default: https://tuist.dev)
- `auth_token`: Authentication token for the server
- `project_id`: Project identifier

## API Implementation

The plugin implements the following C API functions required by the Swift build system:

### Core Functions
- `llcas_get_plugin_version`: Returns plugin version (0.1)
- `llcas_cas_options_create/dispose`: CAS configuration management
- `llcas_cas_create/dispose`: Creates and destroys CAS instances
- `llcas_cas_store_object`: Stores objects by content hash
- `llcas_cas_load_object`: Loads objects by ID
- `llcas_cas_contains_object`: Checks if object exists

### Action Cache Functions
- `llcas_actioncache_put_for_digest`: Caches build results (sync)
- `llcas_actioncache_get_for_digest`: Retrieves cached results (sync)
- `llcas_actioncache_put_for_digest_async`: Async cache storage
- `llcas_actioncache_get_for_digest_async`: Async cache retrieval

### Digest and Object Management
- `llcas_digest_parse/print`: Convert between digest formats
- `llcas_objectid_get_digest`: Get digest from object ID
- `llcas_cas_get_objectid`: Get object ID from digest
- `llcas_loaded_object_get_data/refs`: Access object data and references

### Memory Management
- `llcas_string_dispose`: Deallocates C strings
- `llcas_cancellable_cancel/dispose`: Cancellation support

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

## Implementation Status

Current implementation provides:

✅ **Complete C API**: All 31 required functions implemented  
✅ **Dynamic Library**: Builds successfully with Swift Package Manager  
✅ **C Compatibility**: Proper `@_cdecl` exports for swift-build loading  
✅ **Error Handling**: Comprehensive error propagation  
✅ **Memory Management**: Safe pointer handling and cleanup  

🚧 **Future Enhancements**: Currently using mock implementations for server communication. Production usage requires:

- Integration with actual Tuist server HTTP APIs
- Authentication and authorization
- Local disk caching for better performance  
- Compression of stored objects
- Health monitoring and metrics

## Development

This plugin is part of the [Tuist](https://tuist.io) project and integrates with Apple's Swift build system to provide distributed build caching capabilities.
