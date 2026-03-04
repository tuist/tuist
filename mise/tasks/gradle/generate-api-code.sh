#!/bin/bash
#MISE description="Regenerate Gradle plugin API code from the OpenAPI spec"

set -euo pipefail

SPEC_FILE="$MISE_PROJECT_ROOT/cli/Sources/TuistServer/OpenAPI/server.yml"
TARGET_DIR="$MISE_PROJECT_ROOT/gradle/src/main/kotlin/dev/tuist/gradle/api"
TMPDIR=$(mktemp -d)

trap "rm -rf $TMPDIR" EXIT

GENERATOR="mise x npm:@openapitools/openapi-generator-cli@2.30.1 --"
GENERATOR_VERSION="7.12.0"

$GENERATOR openapi-generator-cli version-manager set "$GENERATOR_VERSION"

# Generate all models referenced by the Authentication API.
# We use the full model set (--global-property models) because filtered
# model lists don't work reliably with inline schema name mappings.
$GENERATOR openapi-generator-cli generate \
  -i "$SPEC_FILE" \
  -g kotlin \
  -o "$TMPDIR" \
  --api-package dev.tuist.gradle.api \
  --model-package dev.tuist.gradle.api.model \
  --additional-properties=library=jvm-retrofit2,serializationLibrary=gson,enumPropertyNaming=original,useCoroutines=false \
  --inline-schema-name-mappings "refreshToken_request=RefreshTokenBody" \
  --global-property apis=Authentication \
  --global-property models \
  --global-property supportingFiles=false

MODEL_SRC="$TMPDIR/src/main/kotlin/dev/tuist/gradle/api/model"

# Copy only the models we need
mkdir -p "$TARGET_DIR/model"
cp "$MODEL_SRC/AuthenticationTokens.kt" "$TARGET_DIR/model/"
cp "$MODEL_SRC/RefreshTokenBody.kt" "$TARGET_DIR/model/"
cp "$MODEL_SRC/CacheEndpoints.kt" "$TARGET_DIR/model/"

echo ""
echo "Updated model files in $TARGET_DIR/model/"
echo ""
echo "NOTE: The API interfaces (AuthenticationApi.kt, CacheApi.kt) are"
echo "hand-maintained because the generator produces invalid Kotlin for"
echo "this spec. If the OpenAPI spec changes the request/response shapes"
echo "for refreshToken or getCacheEndpoints, update those files manually."
