#shellcheck shell=bash
# End-to-end specs for `once cache stats`.

Describe 'once cache stats'
  BeforeEach 'setup_workspace'
  AfterEach 'cleanup_workspace'

  It 'reports zero counts on an empty workspace'
    When call once cache stats
    The status should be success
    The stdout should include 'blobs:   0'
    The stdout should include 'actions: 0'
  End

  It 'counts blobs and actions after an exec'
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hello' >/dev/null 2>&1
    When call once cache stats
    The status should be success
    # One action plus stdout + stderr blobs (stderr may be empty but is
    # still stored as the empty-blob entry).
    The stdout should match pattern '*blobs:   [12]*'
    The stdout should match pattern '*actions: 1*'
  End

  It 'emits a single JSON object under --format json'
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hi' >/dev/null 2>&1
    When call "$ONCE_BIN" --format json -C "$WORKSPACE" cache stats
    The status should be success
    The stdout should include '"blobs":'
    The stdout should include '"actions":'
    The stdout should include '"count":'
    The stdout should include '"bytes":'
  End

  It 'emits a single TOON object under --format toon'
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hi' >/dev/null 2>&1
    When call "$ONCE_BIN" --format toon -C "$WORKSPACE" cache stats
    The status should be success
    The stdout should include 'blobs:'
    The stdout should include 'actions:'
    The stdout should include 'count:'
    The stdout should include 'bytes:'
  End
End
