#!/bin/bash
#MISE description="Regenerate Gradle plugin API code from the OpenAPI spec"

set -euo pipefail

SPEC_FILE="$MISE_PROJECT_ROOT/cli/Sources/TuistServer/OpenAPI/server.yml"
TARGET_DIR="$MISE_PROJECT_ROOT/gradle/src/main/kotlin/dev/tuist/gradle/api"
TMPDIR_AUTH=$(mktemp -d)
TMPDIR_SHARDS=$(mktemp -d)

trap "rm -rf $TMPDIR_AUTH $TMPDIR_SHARDS" EXIT

GENERATOR="mise x npm:@openapitools/openapi-generator-cli@2.30.1 --"
GENERATOR_VERSION="7.12.0"

$GENERATOR openapi-generator-cli version-manager set "$GENERATOR_VERSION"

COMMON_OPTS=(
  -i "$SPEC_FILE"
  -g kotlin
  --api-package dev.tuist.gradle.api
  --model-package dev.tuist.gradle.api.model
  --additional-properties=library=jvm-retrofit2,serializationLibrary=gson,enumPropertyNaming=original
  --inline-schema-name-mappings "refreshToken_request=RefreshTokenBody"
  --global-property models
  --global-property supportingFiles=false
)

# Generate Authentication API + models
$GENERATOR openapi-generator-cli generate "${COMMON_OPTS[@]}" -o "$TMPDIR_AUTH" --global-property apis=Authentication

# Generate Shards API + models
$GENERATOR openapi-generator-cli generate "${COMMON_OPTS[@]}" -o "$TMPDIR_SHARDS" --global-property apis=Shards

AUTH_MODEL="$TMPDIR_AUTH/src/main/kotlin/dev/tuist/gradle/api/model"
SHARDS_MODEL="$TMPDIR_SHARDS/src/main/kotlin/dev/tuist/gradle/api/model"
SHARDS_API="$TMPDIR_SHARDS/src/main/kotlin/dev/tuist/gradle/api"

mkdir -p "$TARGET_DIR/model"

# Authentication models
cp "$AUTH_MODEL/AuthenticationTokens.kt" "$TARGET_DIR/model/"
cp "$AUTH_MODEL/RefreshTokenBody.kt" "$TARGET_DIR/model/"
cp "$AUTH_MODEL/CacheEndpoints.kt" "$TARGET_DIR/model/"

# Shard models
cp "$SHARDS_MODEL/Shard.kt" "$TARGET_DIR/model/"
cp "$SHARDS_MODEL/ShardPlan.kt" "$TARGET_DIR/model/"
cp "$SHARDS_MODEL/ShardPlanShardsInner.kt" "$TARGET_DIR/model/"
cp "$SHARDS_MODEL/CreateShardPlanParams1.kt" "$TARGET_DIR/model/"

# NOTE: ShardsApi.kt is hand-maintained because the generated version includes
# endpoints not used by the Gradle plugin (multipart upload, URL generation)
# which pull in models we don't need. Only createShardPlan and getShard are used.

echo ""
echo "Updated generated files in $TARGET_DIR/"
echo ""
echo "NOTE: AuthenticationApi.kt, CacheApi.kt, and ShardsApi.kt are hand-maintained."
echo "Model files are generated — do not edit manually."
