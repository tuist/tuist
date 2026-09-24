# shellcheck shell=bash

Describe 'Xcode analytics output filtering'
  Include spec/e2e/xcode_analytics_support.sh

  filter_multiple_empty_outputs() {
    printf '%s\n' '0~empty-first' '0~transferred' '0~empty-second' |
      filter_xcode_empty_outputs "$(printf '%s\n' '0~empty-first' '0~empty-second')"
  }

  It 'excludes every empty node when SQLite returns multiple rows'
    When call filter_multiple_empty_outputs
    The status should be success
    The output should equal '0~transferred'
  End
End

Describe 'Xcode compilation-cache transfer analytics'
  Include spec/e2e/xcode_chunking_support.sh
  Include spec/e2e/xcode_analytics_support.sh
  BeforeAll 'setup_xcode_analytics'
  AfterEach 'stop_xcode_proxy'
  AfterAll 'teardown_xcode_chunking'

  It 'joins uploaded compiler outputs to their recorded transfer sizes'
    Skip if 'requires Apple silicon, Xcode, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    When call check_xcode_analytics base-compiled uploaded
    The status should be success
    The output should include 'matched all'
  End

  It 'joins remotely restored compiler outputs to their recorded transfer sizes'
    Skip if 'requires Apple silicon, Xcode, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    run_xcode_phase analytics-restore base analytics-reader false || return 1
    When call check_xcode_analytics analytics-restore using
    The status should be success
    The output should include 'matched all'
    The value "$(xcode_hits analytics-restore)" should equal '4/4'
  End
End
