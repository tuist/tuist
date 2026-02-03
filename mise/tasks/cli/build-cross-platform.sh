#!/usr/bin/env bash
#MISE description="Build the tuist CLI for Linux."
#USAGE flag "-v --linux-vm" help="Build virtualizing Linux"

if command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
else
    CONTAINER_ENGINE="docker"
fi

if [ "$usage_linux_vm" = "true" ]; then
    # Use separate build path for Linux to avoid conflicts with macOS build artifacts
    $CONTAINER_ENGINE run --rm \
            --volume "$MISE_PROJECT_ROOT:/package" \
            --workdir "/package" \
            swift:6.1 \
            swift build --target tuist --build-path .build-linux --replace-scm-with-registry
else
    swift build --target tuist --replace-scm-with-registry
fi
