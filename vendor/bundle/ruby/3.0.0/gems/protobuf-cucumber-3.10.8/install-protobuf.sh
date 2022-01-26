#!/usr/bin/env sh

set -ex

gdie() {
    echo "$@" >&2
    exit 1
}

test -n "$PROTOBUF_VERSION" || die "PROTOBUF_VERSION env var is undefined"

case "$PROTOBUF_VERSION" in
2*)
    basename=protobuf-$PROTOBUF_VERSION
    ;;
3*)
    basename=protobuf-cpp-$PROTOBUF_VERSION
    ;;
*)
    die "unknown protobuf version: $PROTOBUF_VERSION"
    ;;
esac

curl -sL https://github.com/google/protobuf/releases/download/v$PROTOBUF_VERSION/$basename.tar.gz | tar zx

cd protobuf-$PROTOBUF_VERSION

./configure --prefix=/usr && make -j2 && make install
