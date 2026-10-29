#!/bin/sh
set -eu
cd /tmp/resume-ci
# Compile the package and its test bundle. This measures a reproducible build;
# upstream test execution is separate from this VM lifecycle experiment.
swift build --build-tests --jobs 8
