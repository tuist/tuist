# shellcheck shell=bash

Describe 'ByteStream response admission'
  Skip if 'native Kura is not configured' test -z "${KURA_BYTESTREAM_BINARY:-}"
  Skip if 'load client is not configured' test -z "${KURA_BYTESTREAM_CLIENT:-}"

  run_burst() (
    local output
    output="$(mktemp -d)" || return 1
    trap 'rm -rf "$output"' EXIT
    python3 "${KURA_PROJECT_ROOT}/test/e2e/bytestream-admission/run.py" \
      "${KURA_BYTESTREAM_BINARY:?}" "${KURA_BYTESTREAM_CLIENT:?}" "$output" \
      --profile "${KURA_BYTESTREAM_PROFILE:-small}" 2>&1
  )

  It 'serves a burst of paced readers without rejecting or corrupting reads'
    When call run_burst
    The status should be success
    The output should include 'codes=map[OK:128]'
  End
End
