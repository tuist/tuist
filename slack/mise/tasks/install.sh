#!/usr/bin/env bash
#MISE description="Install slack dependencies"
set -euo pipefail

mix local.hex --force
mix local.rebar --force
mix deps.get
