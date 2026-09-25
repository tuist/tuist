#shellcheck shell=bash
# End-to-end specs for direct cache access commands.

Describe 'once cache runtime commands'
  BeforeEach 'setup_workspace'
  AfterEach 'cleanup_workspace'

  It 'stores and fetches a blob from stdin'
    digest="$(printf 'hello cache' | once cache blob put)"
    When call once cache blob get "$digest"
    The status should be success
    The stdout should equal 'hello cache'
  End

  It 'stores a file blob and writes it back to an output path'
    printf 'file payload' > "$WORKSPACE/input.txt"
    digest="$(once cache blob put "$WORKSPACE/input.txt")"
    When call once cache blob get "$digest" --output "$WORKSPACE/out/nested.txt"
    The status should be success
    The stdout should include 'wrote 12 bytes'
    The contents of file "$WORKSPACE/out/nested.txt" should equal 'file payload'
  End

  It 'stores and fetches an action result by positional digest'
    stdout_digest="$(printf 'out' | once cache blob put)"
    stderr_digest="$(printf 'err' | once cache blob put)"
    # Action digests and blob digests are both 64-hex but live in
    # different conceptual namespaces; keep them visibly distinct so
    # the test mirrors what real callers would write.
    action_digest="$(printf 'action-key:by-digest-spec' | once cache blob put)"

    once cache action put "$action_digest" \
      --exit-code 7 \
      --stdout "$stdout_digest" \
      --stderr "$stderr_digest" \
      --output bin/tool="$stdout_digest" >/dev/null

    When call once cache action get "$action_digest"
    The status should be success
    The stdout should include '"exit_code": 7'
    The stdout should include '"stdout": "'$stdout_digest'"'
    The stdout should include '"bin/tool": "'$stdout_digest'"'
  End

  It 'puts and gets an action result by --input declaration'
    printf 'src bytes' > "$WORKSPACE/src.txt"

    once cache action put \
      --input "$WORKSPACE/src.txt" \
      --input value:vitest \
      --output bin/tool=0000000000000000000000000000000000000000000000000000000000000000 \
      >/dev/null

    When call "$ONCE_BIN" --format json -C "$WORKSPACE" cache action get \
      --input "$WORKSPACE/src.txt" \
      --input value:vitest
    The status should be success
    The stdout should include '"hit":true'
    The stdout should include '"exit_code":0'
  End

  It 'derives different action keys from different env values'
    ONCE_TEST_KEY=alpha once cache action put --input env:ONCE_TEST_KEY >/dev/null

    export ONCE_TEST_KEY=beta
    When call once cache action get --input env:ONCE_TEST_KEY --if-success
    # alpha and beta must derive different action digests, so the
    # lookup keyed on beta must miss the alpha record.
    The status should be failure
  End

  It 'walks a directory deterministically when used as --input'
    mkdir -p "$WORKSPACE/tree/nested"
    printf 'alpha' > "$WORKSPACE/tree/a.txt"
    printf 'beta'  > "$WORKSPACE/tree/b.txt"
    printf 'gamma' > "$WORKSPACE/tree/nested/c.txt"

    once cache action put --input "$WORKSPACE/tree" >/dev/null
    # Touching mtime without content change must not move the digest.
    touch "$WORKSPACE/tree/a.txt"
    When call once cache action get --input "$WORKSPACE/tree" --if-success
    The status should be success
  End

  It 'rederives an action key when a directory file changes'
    mkdir -p "$WORKSPACE/tree"
    printf 'first' > "$WORKSPACE/tree/a.txt"
    once cache action put --input "$WORKSPACE/tree" >/dev/null

    printf 'second' > "$WORKSPACE/tree/a.txt"
    When call once cache action get --input "$WORKSPACE/tree" --if-success
    The status should be failure
  End

  It 'defaults --exit-code to 0 on put'
    once cache action put --input value:silent-success >/dev/null

    When call "$ONCE_BIN" --format json -C "$WORKSPACE" cache action get \
      --input value:silent-success
    The status should be success
    The stdout should include '"exit_code":0'
  End

  It 'records an action result without stdout or stderr'
    once cache action put --input value:silent >/dev/null

    When call "$ONCE_BIN" --format json -C "$WORKSPACE" cache action get \
      --input value:silent
    The status should be success
    The stdout should include '"hit":true'
    The stdout should include '"exit_code":0'
    The stdout should not include '"stdout"'
    The stdout should not include '"stderr"'
  End

  It 'restores an output blob recorded under an action declared by inputs'
    payload_digest="$(printf 'tarball-bytes' | once cache blob put)"
    printf 'pkg' > "$WORKSPACE/pkg.json"
    printf 'lock' > "$WORKSPACE/lock.json"

    once cache action put \
      --input "$WORKSPACE/pkg.json" \
      --input "$WORKSPACE/lock.json" \
      --output node_modules.tar="$payload_digest" \
      >/dev/null

    "$ONCE_BIN" --format json -C "$WORKSPACE" cache action get \
      --input "$WORKSPACE/pkg.json" \
      --input "$WORKSPACE/lock.json" \
      > "$WORKSPACE/result.json"
    output_digest="$(sed -nE 's/.*"node_modules\.tar":"([0-9a-f]+)".*/\1/p' "$WORKSPACE/result.json")"

    When call once cache blob get "$output_digest"
    The status should be success
    The stdout should equal 'tarball-bytes'
  End

  It 'forgets an action result'
    once cache action put --input value:to-forget >/dev/null

    # Resolve the digest via a JSON get so we can pass it positionally
    # to forget (which only takes a digest, not --input).
    "$ONCE_BIN" --format json -C "$WORKSPACE" cache action get \
      --input value:to-forget > "$WORKSPACE/result.json"
    action_digest="$(sed -nE 's/.*"action":"([0-9a-f]+)".*/\1/p' "$WORKSPACE/result.json")"

    When call once cache action forget "$action_digest"
    The status should be success
    The stdout should include 'forgot action'
  End

  It 'reports an action miss as JSON'
    When call "$ONCE_BIN" --format json -C "$WORKSPACE" cache action get \
      --input value:never-recorded
    The status should be success
    The stdout should include '"hit":false'
  End

  It '--if-success exits 0 on a cached success'
    once cache action put --input value:ok-run >/dev/null

    When call once cache action get --input value:ok-run --if-success
    The status should be success
  End

  It '--if-success exits non-zero on a cache miss'
    When call once cache action get --input value:never-recorded --if-success
    The status should be failure
  End

  It '--if-success exits non-zero on a cached failure'
    once cache action put --input value:flaky-run --exit-code 1 >/dev/null

    When call once cache action get --input value:flaky-run --if-success
    The status should be failure
  End

  It 'exits 0 when blob exists'
    digest="$(printf 'present' | once cache blob put)"
    When call once cache blob exists "$digest"
    The status should be success
  End

  It 'exits non-zero when blob is missing'
    When call once cache blob exists 0000000000000000000000000000000000000000000000000000000000000000
    The status should be failure
  End

  It 'reports blob existence as JSON without erroring on miss'
    When call "$ONCE_BIN" --format json -C "$WORKSPACE" cache blob exists \
      0000000000000000000000000000000000000000000000000000000000000000
    The status should be success
    The stdout should include '"present":false'
  End

  It 'fails with a clear message when fetching a missing blob'
    When call once cache blob get 0000000000000000000000000000000000000000000000000000000000000000
    The status should be failure
    The stderr should include 'blob not found'
  End

  It 'fails with a clear message when putting a non-existent file'
    When call once cache blob put "$WORKSPACE/does-not-exist"
    The status should be failure
    The stderr should include 'opening blob input'
  End

  It 'rejects a malformed digest argument'
    When call once cache blob get not-a-hex-digest
    The status should be failure
    The stderr should include 'BLAKE3'
  End
End
