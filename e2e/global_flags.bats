#!/usr/bin/env bats

setup() {
    load 'test_helper'
    require_env TUIST_EXECUTABLE

    unset TUIST_CONFIG_VERBOSE TUIST_CONFIG_QUIET
    export TUIST_XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
    export TUIST_XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
    export TUIST_XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"

    mkdir -p "${BATS_TEST_TMPDIR}/project"
    cd "${BATS_TEST_TMPDIR}/project" || return 1
    cat > Project.swift <<'EOF'
import ProjectDescription
import ProjectDescriptionHelpers

let project = makeProject()
EOF
    cat > Tuist.swift <<'EOF'
import ProjectDescription

let tuist = Tuist()
EOF
    mkdir -p Tuist/ProjectDescriptionHelpers
    cat > Tuist/ProjectDescriptionHelpers/Project.swift <<'EOF'
import ProjectDescription

public func makeProject() -> Project {
    Project(name: "GlobalFlags", targets: [])
}
EOF
}

@test "verbose enables debug output before or after the command, overriding a false environment value" {
    export TUIST_CONFIG_VERBOSE=0

    run "$TUIST_EXECUTABLE" generate --no-open
    [ "$status" -eq 0 ]
    [[ "$output" != *"Generating project config for GlobalFlags"* ]]

    run "$TUIST_EXECUTABLE" generate --no-open --verbose
    [ "$status" -eq 0 ]
    [[ "$output" == *"Generating project config for GlobalFlags"* ]]

    run "$TUIST_EXECUTABLE" --verbose generate --no-open
    [ "$status" -eq 0 ]
    [[ "$output" == *"Generating project config for GlobalFlags"* ]]
}

@test "quiet overrides verbose logging enabled through the environment" {
    run env TUIST_CONFIG_VERBOSE=1 "$TUIST_EXECUTABLE" generate --no-open --quiet
    [ "$status" -eq 0 ]
    [[ "$output" != *"Generating project config for GlobalFlags"* ]]
    [ -d GlobalFlags.xcworkspace ]
}
