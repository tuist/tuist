#!/usr/bin/env bash
#MISE description="Build the targets that have been verified to be cross-platform."
#USAGE flag "-v --linux-vm" help="Build virtualizing Linux"

if command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
else
    CONTAINER_ENGINE="docker"
fi

# We'll gradually traverse the graph ensuring targets, and their dependency trees,
# support macOS, Linux, and Windows. Once a target has been verified to compile for all platforms,
# we'll include it below
target_flags="--target ProjectDescription"

if [ "$usage_linux_vm" = "true" ]; then
    $CONTAINER_ENGINE run --rm \
            --volume "$MISE_PROJECT_ROOT:/package" \
            --workdir "/package" \
            swiftlang/swift:nightly-6.0-focal \
            /bin/bash -c \
            "swift build --build-path ./.build/linux $target_flags"
else
    swift build $target_flags
fi
