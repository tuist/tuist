#!/bin/bash
#MISE description="Generates Swift protobuf files for the tuist-cache-proxy executable"

cd "$MISE_PROJECT_ROOT"/cli/Sources/TuistCAS

# Scoped with `mise x`, not the global [tools] table: the SwiftPM backend builds these with `swift`,
# so an unscoped `mise install` on a Swift-less Linux runner fails. Versions track Package.swift.
mise x spm:grpc/grpc-swift-protobuf@2.1.1 -- protoc --grpc-swift-2_out=Generated --grpc-swift-2_opt=Visibility=Public keyvalue.proto cas.proto
mise x spm:apple/swift-protobuf@1.35.1 -- protoc --swift_out=Generated --swift_opt=Visibility=Public keyvalue.proto cas.proto

echo "Generated protobuf files for tuist-cache-proxy"
