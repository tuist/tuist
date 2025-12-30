#!/usr/bin/env bash
#MISE description="Install cache dependencies"
set -euo pipefail

mix local.hex --force
mix local.rebar --force
mix deps.get
