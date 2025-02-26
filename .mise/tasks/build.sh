#!/usr/bin/env bash
#MISE description="Builds the part of the graph that we know compiles for macOS, Linux, and Windows."

#USAGE flag "-v --linux-vm" help="Build virtualizing Linux"

if command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
else
    CONTAINER_ENGINE="docker"
fi

# This is a list of dependencies that we've verified that compile for Linux and Windows.
# The plan is to extend this list, eventually including local targets, until we make sure
# the entire graph compiles for both platforms.
CHECKED_DEPENDENCIES=("AEXML")

if [ "$usage_linux_vm" != "true" ]; then
    swift package resolve
fi

for dependency in "${CHECKED_DEPENDENCIES[@]}"; do
    if [ "$usage_linux_vm" = "true" ]; then
        $CONTAINER_ENGINE run --rm \
                --volume "$MISE_PROJECT_ROOT:/package" \
                --workdir "/package" \
                swiftlang/swift:nightly-6.0-focal \
                /bin/bash -c \
                "swift package resolve && swift build --package-path .build/checkouts/$dependency"
    else
        swift build --package-path .build/checkouts/$dependency
    fi
done
