#!/usr/bin/env bash
# mise description="Seeds data into the database for local development"

set -euo pipefail

(cd server && mix run priv/repo/timezone.exs)
(cd server && mix run priv/repo/seeds.exs)
