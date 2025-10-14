#!/bin/bash
#MISE description="Generates Swift protobuf files for the tuist-cache-proxy executable"

cd "$MISE_PROJECT_ROOT"/cli/Sources/tuist-cas-proxy
mise x spm:grpc/grpc-swift-protobuf@2.1.1 -- protoc --plugin=$(which protoc-gen-grpc-swift-2) --grpc-swift-2_out=Generated keyvalue.proto cas.proto
protoc --swift_out=Generated keyvalue.proto cas.proto

echo "Generated protobuf files for tuist-cache-proxy"
