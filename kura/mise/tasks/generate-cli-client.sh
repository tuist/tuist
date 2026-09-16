#!/usr/bin/env bash
#MISE description="Generate the CLI's Swift cache client (cli/Sources/TuistCache/OpenAPI) from Kura's HTTP API definition in openapi/cache.yml."
set -euo pipefail

cd "$(dirname "$0")/../.."

output=../cli/Sources/TuistCache/OpenAPI
cp openapi/cache.yml "${output}/cache.yml"
mise x spm:apple/swift-openapi-generator@1.10.3 -- swift-openapi-generator generate \
  --mode types \
  --access-modifier public \
  --mode client \
  --output-directory "${output}" \
  "${output}/cache.yml"
