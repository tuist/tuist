#!/bin/bash
#MISE description="Generates Swift protobuf files for the vendored REAPI Capabilities service (TuistREAPI)"

set -euo pipefail

cd "$MISE_PROJECT_ROOT"/cli/Sources/TuistREAPI

protoc --swift_out=Generated --swift_opt=Visibility=Public capabilities.proto
protoc --grpc-swift-2_out=Generated --grpc-swift-2_opt=Visibility=Public capabilities.proto

# The grpc-swift-2 generator emits a `type:` argument on MethodDescriptor that the resolved
# grpc-swift-2 runtime does not accept yet; drop it until the runtime catches up. perl keeps this
# portable across the BSD/GNU sed split.
perl -0pi -e 's/,\s*type:\s*\.unary//g' Generated/capabilities.grpc.swift

swiftformat Generated/capabilities.pb.swift Generated/capabilities.grpc.swift

echo "Generated protobuf files for TuistREAPI"
