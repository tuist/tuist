# shellcheck shell=bash

Describe 'Clang chunk-transfer fault recovery'
  Include spec/e2e/xcode_chunking_support.sh
  Include spec/e2e/clang_chunking_support.sh
  BeforeAll 'setup_clang_chunking'
  AfterEach 'stop_clang_gate'
  AfterAll 'teardown_clang_chunking'

  It 'does not advertise an interrupted chunk upload and recompiles on a fresh reader'
    Skip if 'requires Apple silicon, Xcode 26, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    start_clang_gate interrupted interrupt-upload || return 1
    start_clang_proxy interrupted-writer || return 1
    build_clang_fixture interrupted-writer true || return 1
    drain_status=0
    drain_clang_upload interrupted-writer || drain_status=$?
    finish_clang_phase interrupted-writer || return 1

    printf 'pass\n' >"$CLANG_TEST_CONTROL/mode"
    start_clang_proxy interrupted-reader || return 1
    build_clang_fixture interrupted-reader false || return 1
    finish_clang_phase interrupted-reader || return 1
    When call compare_clang_output interrupted-writer interrupted-reader
    The status should be success
    The value "$drain_status" should equal 3
    The contents of file "$CLANG_TEST_CONTROL/events" should include 'interrupted-upload'
    The contents of file "$CLANG_TEST_CONTROL/events" should not include 'action-put'
    The value "$(clang_hits interrupted-reader)" should equal '0/1'
  End

  It 'recompiles safely when remote chunks disappear after the action and recipe were returned'
    Skip if 'requires Apple silicon, Xcode 26, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    start_clang_gate evicted pass || return 1
    start_clang_proxy eviction-writer || return 1
    build_clang_fixture eviction-writer true || return 1
    drain_clang_upload eviction-writer || return 1
    finish_clang_phase eviction-writer || return 1

    evict_during_clang_restore evicted-reader || return 1
    compare_clang_output eviction-writer evicted-reader || return 1
    printf 'pass\n' >"$CLANG_TEST_CONTROL/mode"
    start_clang_proxy repaired-reader || return 1
    build_clang_fixture repaired-reader false || return 1
    finish_clang_phase repaired-reader || return 1

    When call compare_clang_output eviction-writer repaired-reader
    The status should be success
    The contents of file "$CLANG_TEST_CONTROL/events" should include 'splice-completed'
    The contents of file "$CLANG_TEST_CONTROL/events" should include 'action-hit'
    The contents of file "$CLANG_TEST_CONTROL/events" should include 'recipe-returned'
    The contents of file "$CLANG_TEST_CONTROL/events" should include 'chunk-missing'
    The contents of file "$CLANG_TEST_CONTROL/events" should include 'whole-missing'
    The value "$(clang_hits evicted-reader)" should equal '0/1'
    The value "$(clang_hits repaired-reader)" should equal '1/1'
  End

  It 'restores a healthy Clang hit and keeps the complete graph usable after restart and remote deletion'
    Skip if 'requires Apple silicon, Xcode 26, local Kura, and KURA_E2E_XCODE=1' xcode_chunking_disabled
    xcode_chunking_enabled || return 0

    start_clang_gate healthy pass || return 1
    start_clang_proxy healthy-writer || return 1
    build_clang_fixture healthy-writer true || return 1
    drain_clang_upload healthy-writer || return 1
    finish_clang_phase healthy-writer || return 1

    start_clang_proxy healthy-reader || return 1
    build_clang_fixture healthy-reader false || return 1
    finish_clang_phase healthy-reader || return 1
    compare_clang_output healthy-writer healthy-reader || return 1

    curl --fail --silent --max-time 10 -X DELETE --get \
      --data-urlencode 'tenant_id=chunking-test' \
      --data-urlencode "namespace_id=${CLANG_TEST_INSTANCE#chunking-test/}" \
      "$CLANG_TEST_URL/api/cache/clean" >/dev/null || return 1
    mkdir "$CLANG_TEST_DERIVED" || return 1
    mv "$CLANG_TEST_ROOT/healthy-reader/CompilationCache.noindex" "$CLANG_TEST_DERIVED/" || return 1
    start_clang_proxy healthy-restarted || return 1
    build_clang_fixture healthy-restarted false || return 1
    finish_clang_phase healthy-restarted || return 1

    When call compare_clang_output healthy-writer healthy-restarted
    The status should be success
    The value "$(clang_hits healthy-reader)" should equal '1/1'
    The value "$(clang_hits healthy-restarted)" should equal '1/1'
    The contents of file "$CLANG_TEST_CONTROL/events" should include 'recipe-returned'
  End
End
