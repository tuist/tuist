# Registry End-to-End Testing Guide

This guide documents how to manually test the Swift Package Registry implementation on cache nodes.

## Prerequisites

- Local cache server running
- MinIO or S3-compatible storage for testing
- Swift toolchain installed (5.9+)
- `tuist` CLI installed

## Test Environment Setup

### 1. Start MinIO (Local S3)

```bash
# Start MinIO with default credentials
docker run -d \
  --name minio \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio server /data --console-address ":9001"

# Create the cache bucket
docker exec minio mc alias set local http://localhost:9000 minioadmin minioadmin
docker exec minio mc mb local/tuist-cache
```

### 2. Configure Cache Server

Set environment variables for local testing:

```bash
export S3_BUCKET=tuist-cache
export S3_ENDPOINT=http://localhost:9000
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export SERVER_URL=https://tuist.dev  # For syncing metadata
```

### 3. Start Cache Server

```bash
cd cache
mix deps.get
mix phx.server
```

The server will start on `http://localhost:4000`.

## Test Scenarios

### Scenario 1: Package Exists in Registry

**Setup**: Ensure a package exists in the registry metadata.

**Test**:
```bash
# 1. Check package availability
curl -s http://localhost:4000/api/registry/swift
# Expected: HTTP 200 OK

# 2. List releases for a package
curl -s http://localhost:4000/api/registry/swift/apple/swift-argument-parser
# Expected: {"releases": {"1.2.0": {"url": "/api/registry/swift/apple/swift-argument-parser/1.2.0"}, ...}}

# 3. Get release info
curl -s http://localhost:4000/api/registry/swift/apple/swift-argument-parser/1.2.0
# Expected: {"id": "apple.swift-argument-parser", "version": "1.2.0", "resources": [...]}
```

### Scenario 2: Package Not in Registry

**Test**:
```bash
curl -s http://localhost:4000/api/registry/swift/nonexistent/package
# Expected: HTTP 404 with {"message": "Package not found"}
```

### Scenario 3: Cold Cache (First Request)

**Setup**: Clear local disk cache and ensure package exists in S3.

**Test**:
```bash
# 1. Clear local cache
rm -rf /cas/registry/

# 2. Request source archive
curl -I http://localhost:4000/api/registry/swift/apple/swift-argument-parser/1.2.0.zip

# 3. Check cache server logs for S3 download
# Expected log: "Downloading from S3: registry/swift/apple/swift-argument-parser/1.2.0/source_archive.zip"
```

**Verification**:
- First request may return 404 (triggers background S3 download)
- Subsequent request should return 200 with the file
- Check logs for "S3 download" or "enqueue_registry_download" messages

### Scenario 4: Warm Cache (Subsequent Requests)

**Setup**: Ensure package is already cached on local disk.

**Test**:
```bash
# 1. First request (populates cache)
curl -O http://localhost:4000/api/registry/swift/apple/swift-argument-parser/1.2.0.zip

# 2. Second request (should be served from disk)
time curl -O http://localhost:4000/api/registry/swift/apple/swift-argument-parser/1.2.0.zip
```

**Verification**:
- Second request should be significantly faster
- No "S3 download" log messages for second request
- Check nginx logs for `X-Accel-Redirect` to `/internal/local/` path

### Scenario 5: SwiftPM Integration Test

**Setup**: Create a test Swift package that uses the registry.

**1. Configure SwiftPM to use local registry**:

```bash
# Run tuist registry setup pointing to local cache
tuist registry setup --server-url http://localhost:4000
```

This creates `~/.swiftpm/configuration/registries.json`:
```json
{
  "registries": {
    "[default]": {
      "url": "http://localhost:4000/api/registry/swift"
    }
  },
  "version": 1
}
```

**2. Create test package**:

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RegistryTest",
    dependencies: [
        .package(id: "apple.swift-argument-parser", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "RegistryTest",
            dependencies: [
                .product(name: "ArgumentParser", package: "apple.swift-argument-parser")
            ]
        )
    ]
)
```

**3. Resolve dependencies**:

```bash
swift package resolve
```

**Expected**: Package resolves successfully from the local registry.

## Verification Signals

### Cold Cache Indicators

- Cache server logs show: `Downloading from S3: registry/swift/...`
- S3 transfer queue has pending downloads
- First request may return 404 or take longer

### Warm Cache Indicators

- No S3 download logs for the request
- nginx logs show `X-Accel-Redirect: /internal/local/...`
- Response time is fast (< 100ms for small files)

### Log Locations

- Cache server logs: stdout when running `mix phx.server`
- nginx access logs: `/var/log/nginx/access.log` (if using nginx)
- S3 transfer queue: Check `s3_transfers` table in SQLite

## Troubleshooting

### Package Not Found

1. Verify metadata exists in S3: `registry/metadata/{scope}/{name}/index.json`
2. Check sync worker has run: Look for `SyncWorker` logs
3. Verify leader election: Check `registry/sync/leader.lock` in S3

### Source Archive Download Fails

1. Check S3 connectivity: `curl http://localhost:9000/minio/health/live`
2. Verify archive exists in S3: `registry/swift/{scope}/{name}/{version}/source_archive.zip`
3. Check S3 transfer worker logs for errors

### SwiftPM Resolution Fails

1. Verify registries.json is correctly configured
2. Check registry availability: `curl http://localhost:4000/api/registry/swift`
3. Ensure package identifier matches: `{scope}.{name}` format

## Cleanup

```bash
# Stop MinIO
docker stop minio && docker rm minio

# Clear local cache
rm -rf /cas/registry/

# Reset SwiftPM configuration
rm ~/.swiftpm/configuration/registries.json
```
