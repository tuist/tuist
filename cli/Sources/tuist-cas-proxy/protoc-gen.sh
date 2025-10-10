#!/bin/sh

protoc --plugin=/Users/marekfort/Downloads/grpc-swift-protobuf/.build/debug/protoc-gen-grpc-swift-2 --grpc-swift-2_out=Generated keyvalue.proto
protoc --swift_out=Generated keyvalue.proto
protoc --plugin=/Users/marekfort/Downloads/grpc-swift-protobuf/.build/debug/protoc-gen-grpc-swift-2 --grpc-swift-2_out=Generated cas.proto
protoc --swift_out=Generated cas.proto
