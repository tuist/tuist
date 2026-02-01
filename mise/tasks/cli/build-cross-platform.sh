#!/usr/bin/env bash
#MISE description="Build the tuist CLI for Linux."
#USAGE flag "-v --linux-vm" help="Build virtualizing Linux"

if command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
else
    CONTAINER_ENGINE="docker"
fi

if [ "$usage_linux_vm" = "true" ]; then
    $CONTAINER_ENGINE run --rm \
            --volume "$MISE_PROJECT_ROOT:/package" \
            --workdir "/package" \
            swiftlang/swift:nightly-6.0-focal \
            /bin/bash -c \
            "swift build --target tuist"
else
    swift build --target tuist
fi
