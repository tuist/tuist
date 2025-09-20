#!/usr/bin/env bash
#MISE description="Seeds data into the database for local development"

set -euo pipefail

mix run priv/repo/timezone.exs
mix run priv/repo/seeds.exs
