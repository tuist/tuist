# shellcheck shell=bash

Describe 'Xcode compilation-cache lookups against a distant cache'
  Include spec/e2e/xcode_chunking_support.sh
  Include spec/e2e/xcode_lookups_support.sh
  BeforeAll 'setup_xcode_lookups'
  AfterEach 'stop_lookup_processes'
  AfterAll 'teardown_xcode_lookups'

  It 'asks the cache for missing keys concurrently rather than one at a time'
    Skip if 'requires Apple silicon, Xcode, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    When call run_lookup_phase cold-miss empty false "$(delayed_lookups)"
    The status should be success
    The value "$(lookup_hits cold-miss)" should equal "0/$(lookup_tasks cold-miss)"
    The value "$(lookup_tasks cold-miss)" should satisfy lookup_at_least 20
    The value "$(lookup_count cold-miss)" should satisfy lookup_at_least 20
    The value "$(lookup_concurrency cold-miss)" should satisfy lookup_at_least 4
  End

  It 'restores every task from the cache with concurrent lookups'
    Skip if 'requires Apple silicon, Xcode, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    run_lookup_phase seed warm true none || return 1
    When call run_lookup_phase cold-hit warm false "$(delayed_lookups)"
    The status should be success
    The value "$(lookup_tasks cold-hit)" should satisfy lookup_at_least 20
    The value "$(lookup_hits cold-hit)" should equal "$(lookup_tasks cold-hit)/$(lookup_tasks cold-hit)"
    The value "$(lookup_concurrency cold-hit)" should satisfy lookup_at_least 4
  End
End
