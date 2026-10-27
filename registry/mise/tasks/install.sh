#!/usr/bin/env bash
#MISE description="Install Swift registry dependencies"
set -euo pipefail

mix local.hex --force
mix local.rebar --force
mix deps.get
