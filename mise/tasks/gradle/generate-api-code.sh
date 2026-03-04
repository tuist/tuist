#!/bin/bash
#MISE description="Regenerate Gradle plugin API code from the OpenAPI spec"

set -euo pipefail

SPEC_FILE="$MISE_PROJECT_ROOT/cli/Sources/TuistServer/OpenAPI/server.yml"
OUTPUT_DIR="/tmp/tuist-gradle-api"
TARGET_DIR="$MISE_PROJECT_ROOT/gradle/src/main/kotlin/dev/tuist/gradle/api"

if ! command -v openapi-generator-cli &> /dev/null; then
    echo "Error: openapi-generator-cli is not installed."
    echo "Install it with: brew install openapi-generator"
    exit 1
fi

rm -rf "$OUTPUT_DIR"

openapi-generator-cli generate \
  -i "$SPEC_FILE" \
  -g kotlin \
  -o "$OUTPUT_DIR" \
  --api-package dev.tuist.gradle.api \
  --model-package dev.tuist.gradle.api.model \
  --additional-properties=library=jvm-retrofit2,serializationLibrary=gson,enumPropertyNaming=original,useCoroutines=false \
  --global-property "apis=Authentication,OidcAuthentication,Cache" \
  --global-property "models" \
  --global-property "supportingFiles=false"

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR/model"

# Copy generated API interfaces
if [ -d "$OUTPUT_DIR/src/main/kotlin/dev/tuist/gradle/api" ]; then
    find "$OUTPUT_DIR/src/main/kotlin/dev/tuist/gradle/api" -maxdepth 1 -name "*.kt" -exec cp {} "$TARGET_DIR/" \;
fi

# Copy generated model classes
if [ -d "$OUTPUT_DIR/src/main/kotlin/dev/tuist/gradle/api/model" ]; then
    cp "$OUTPUT_DIR/src/main/kotlin/dev/tuist/gradle/api/model/"*.kt "$TARGET_DIR/model/" 2>/dev/null || true
fi

rm -rf "$OUTPUT_DIR"

echo "Generated API code in $TARGET_DIR"
