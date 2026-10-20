# shellcheck shell=bash

Describe 'Xcode compilation-cache chunk reuse'
  Include spec/e2e/xcode_chunking_support.sh
  BeforeAll 'setup_xcode_chunking'
  AfterEach 'stop_xcode_proxy'
  AfterAll 'teardown_xcode_chunking'

  It 'restores all twelve compiler outputs into an empty compiler store'
    Skip if 'requires Apple silicon, Xcode 26, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    run_xcode_phase cold base cold-reader false || return 1
    When call compare_xcode_outputs base-compiled cold
    The status should be success
    The value "$(xcode_hits cold)" should equal '4/4'
    The value "$(xcode_counter cold batch_download_bytes)" should satisfy xcode_greater_than 0
  End

  It 'reuses local chunks after restarting the reader and cleaning the compiler store'
    Skip if 'requires Apple silicon, Xcode 26, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    run_xcode_phase restart-seed base restart-reader false || return 1
    run_xcode_phase restarted base restart-reader false || return 1
    When call compare_xcode_outputs base-compiled restarted
    The status should be success
    The value "$(xcode_hits restarted)" should equal '4/4'
    The value "$(xcode_counter restarted reused_chunk_bytes)" should satisfy xcode_greater_than 0
    The value "$(xcode_counter restarted batch_download_bytes)" should satisfy xcode_less_than "$(xcode_counter restart-seed batch_download_bytes)"
  End

  It 'reuses base chunks while restoring the exact outputs of a property rename'
    Skip if 'requires Apple silicon, Xcode 26, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    run_xcode_phase edit-seed base edit-reader false || return 1
    run_xcode_phase edited edited edit-reader false || return 1
    When call compare_xcode_outputs edited-compiled edited
    The status should be success
    The value "$(xcode_hits edited)" should equal '4/4'
    The value "$(xcode_counter edited reused_chunk_bytes)" should satisfy xcode_greater_than 0
  End
End
