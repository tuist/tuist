#!/bin/bash
# mise description="Generates the Swift code off the Open API specification."

set -euo pipefail

pushd $MISE_PROJECT_ROOT/server
mix openapi.spec.yaml --spec TuistWeb.API.Spec ../cli/Sources/TuistServer/OpenAPI/server.yml
popd
mise x spm:apple/swift-openapi-generator@1.3.1 -- swift-openapi-generator generate --mode types --mode client --output-directory $MISE_PROJECT_ROOT/cli/Sources/TuistServer/OpenAPI $MISE_PROJECT_ROOT/cli/Sources/TuistServer/OpenAPI/server.yml
