#!/usr/bin/env bash
#MISE description="Test the Tuist Grafana app plugin"
set -euo pipefail
# `test:ci` is the one-shot form (`jest --passWithNoTests --maxWorkers 4`);
# `test` in package.json is `jest --watch --onlyChanged` for local TDD
# loops. The "ci" suffix is the @grafana/create-plugin naming convention;
# both CI runs and headless pre-push hooks want the one-shot form.
pnpm run test:ci
