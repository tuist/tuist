# shellcheck shell=bash

Describe 'Xcode repeated-wipe fixture isolation'
  Include spec/e2e/xcode_lookups_support.sh
  BeforeEach 'setup_lookup_lifecycle'
  AfterEach 'teardown_lookup_lifecycle'

  setup_lookup_lifecycle() {
    LOOKUP_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lookup-lifecycle.XXXXXX")"
    LOOKUP_TEST_DERIVED="$LOOKUP_TEST_ROOT/DerivedData"
    LOOKUP_LIFECYCLE_STATUS=0
    mkdir -p "$LOOKUP_TEST_DERIVED"
    touch "$LOOKUP_TEST_DERIVED/previous-example"
  }

  teardown_lookup_lifecycle() {
    rm -rf "${LOOKUP_TEST_ROOT:?}"
  }

  run_repeated_lookup_wipe_builds() {
    [ ! -e "$LOOKUP_TEST_DERIVED/previous-example" ] || return 2
    mkdir -p "$LOOKUP_TEST_DERIVED"
    touch "$LOOKUP_TEST_DERIVED/replayed-output"
    return "$LOOKUP_LIFECYCLE_STATUS"
  }

  It 'starts clean and retains evidence without contaminating the next example'
    When call run_repeated_lookup_wipes
    The status should be success
    The path "$LOOKUP_TEST_DERIVED" should not be exist
    The path "$LOOKUP_TEST_ROOT/repeated/replayed-output" should be file
  End

  It 'also clears the shared DerivedData path after a build fails'
    LOOKUP_LIFECYCLE_STATUS=1
    When call run_repeated_lookup_wipes
    The status should equal 1
    The path "$LOOKUP_TEST_DERIVED" should not be exist
    The path "$LOOKUP_TEST_ROOT/repeated/replayed-output" should be file
  End

  It 'refuses to remove a path outside the fixture DerivedData directory'
    LOOKUP_TEST_DERIVED="$LOOKUP_TEST_ROOT/protected"
    mkdir -p "$LOOKUP_TEST_DERIVED"
    touch "$LOOKUP_TEST_DERIVED/keep"
    When call run_repeated_lookup_wipes
    The status should equal 1
    The path "$LOOKUP_TEST_DERIVED/keep" should be file
  End
End
