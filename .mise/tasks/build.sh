#!/usr/bin/env bash
#MISE description="Build the project"

#USAGE flag "-s --spm" help="Build through SPM"
#USAGE flag "-v --linux-vm" help="Build virtualizing Linux"

if [ "$usage_spm" = "true" ]; then
    if [ "$usage_linux_vm" = "true" ]; then
        if command -v podman &> /dev/null; then
            CONTAINER_ENGINE="podman"
        else
            CONTAINER_ENGINE="docker"
        fi
        $CONTAINER_ENGINE run --rm \
                --volume "$MISE_PROJECT_ROOT:/package" \
                --workdir "/package" \
                swiftlang/swift:nightly-6.0-focal \
                /bin/bash -c \
                "swift build --build-path ./.build/linux"
    else
        swift build
    fi
else
    tuist build
fi
