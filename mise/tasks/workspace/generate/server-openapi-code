#!/bin/bash
# mise description="Generates the Swift code off the Open API specification."

set -euo pipefail

swift-openapi-generator generate --mode types --mode client --output-directory $MISE_PROJECT_ROOT/cli/Sources/TuistServer/OpenAPI $MISE_PROJECT_ROOT/cli/Sources/TuistServer/OpenAPI/server.yml
