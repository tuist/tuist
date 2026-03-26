#!/bin/bash
#MISE description="Generates the Swift code off the Open API specification."

set -euo pipefail

mix openapi.spec.yaml --spec TuistWeb.API.Spec ../cli/Sources/TuistServer/OpenAPI/server.yml
mise x spm:apple/swift-openapi-generator@1.10.3 -- swift-openapi-generator generate --mode types --access-modifier public --mode client --output-directory ../cli/Sources/TuistServer/OpenAPI ../cli/Sources/TuistServer/OpenAPI/server.yml
