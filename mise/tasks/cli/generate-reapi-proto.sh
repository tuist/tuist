#!/bin/bash
#MISE description="Generates Swift protobuf files for the vendored REAPI cache services (TuistREAPI)"

set -euo pipefail

cd "$MISE_PROJECT_ROOT"/cli/Sources/TuistREAPI

# Keep generator tools scoped to this task: their SwiftPM backend requires Swift,
# which is unavailable on some runners. Explicit plugin paths avoid ambient PATH versions.
mise install spm:apple/swift-protobuf@1.35.1 spm:grpc/grpc-swift-protobuf@2.1.1
protobuf_root=$(mise where spm:apple/swift-protobuf@1.35.1)
grpc_root=$(mise where spm:grpc/grpc-swift-protobuf@2.1.1)
"$protobuf_root/bin/protoc" --plugin="protoc-gen-swift=$protobuf_root/bin/protoc-gen-swift" --swift_out=Generated --swift_opt=Visibility=Public capabilities.proto cache.proto bytestream.proto
"$protobuf_root/bin/protoc" --plugin="protoc-gen-grpc-swift-2=$grpc_root/bin/protoc-gen-grpc-swift-2" --grpc-swift-2_out=Generated --grpc-swift-2_opt=Visibility=Public capabilities.proto cache.proto bytestream.proto

# The grpc-swift-2 generator emits a `type:` argument on MethodDescriptor that the resolved
# grpc-swift-2 runtime does not accept yet; drop it until the runtime catches up. perl keeps this
# portable across the BSD/GNU sed split.
perl -0pi -e 's/,\s*type:\s*\.(unary|serverStreaming|clientStreaming)//g' Generated/*.grpc.swift

swiftformat Generated/*.swift --cache ignore
# The first pass strips the generator header, exposing the proto file comment as another header.
# Normalize that header without the formatter cache masking the second pass.
swiftformat Generated/*.grpc.swift --rules fileHeader --cache ignore

echo "Generated protobuf files for TuistREAPI"
