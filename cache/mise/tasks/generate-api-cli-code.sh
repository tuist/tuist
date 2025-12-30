#!/usr/bin/env bash
#MISE description="Generates the Swift code off the Open API specification."

set -euo pipefail

cd "$(dirname "$0")/../.."

mix openapi.spec.yaml --spec CacheWeb.API.Spec ../cli/Sources/TuistCache/OpenAPI/cache.yml
mise x spm:apple/swift-openapi-generator@1.10.3 -- swift-openapi-generator generate \
  --mode types \
  --access-modifier public \
  --mode client \
  --output-directory ../cli/Sources/TuistCache/OpenAPI \
  ../cli/Sources/TuistCache/OpenAPI/cache.yml
