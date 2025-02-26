#!/usr/bin/env bash
#MISE description="Build the project"

#USAGE flag "-v --linux-vm" help="Build virtualizing Linux"

if command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
else
    CONTAINER_ENGINE="docker"
fi
dependencies=("AEXML")

# Not all the grah modules compile for Linux, so let's
# figure out one by one until we can ensure the whole graph compiles.

if [ "$usage_linux_vm" = "false" ]; then
    swift package resolve
fi

for dependency in "${dependencies[@]}"; do
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
