#!/usr/bin/env bash
#MISE description="Test the Noora web package"
set -euo pipefail
aube --filter noora run test
