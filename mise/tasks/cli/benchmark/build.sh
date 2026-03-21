#!/bin/bash
#MISE description="Build the 'tuistbenchmark' tool"
set -euo pipefail

swift build --target tuistbenchmark $@
