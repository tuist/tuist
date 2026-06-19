# shellcheck shell=bash

# Validates the kura gateway HTTP/2 upload-window fix end to end: it stands up
# the kura gRPC backend behind both the BEFORE (nginx default window) and AFTER
# (the chart's raised window) nginx configs, injects WAN latency with toxiproxy, and
# uploads a blob via REAPI ByteStream through each. The patched window must
# deliver a large throughput speedup, otherwise the gateway change is not
# actually buying anything under latency.
#
# Opt-in: this builds a small Go client image and runs ~30-60s, so it is
# skipped unless KURA_E2E_THROUGHPUT=1. The full harness (and tuning knobs)
# lives in test/e2e/grpc-upload-throughput/.
Describe 'gateway gRPC upload throughput (HTTP/2 window)'
  throughput_dir() { printf '%s/test/e2e/grpc-upload-throughput' "${KURA_PROJECT_ROOT:?missing KURA_PROJECT_ROOT}"; }

  run_throughput() {
    # docker compose streams build/lifecycle output to stderr; fold it into
    # stdout so shellspec doesn't flag it as an unexpected-stderr warning.
    SIZE_MB="${KURA_E2E_THROUGHPUT_SIZE_MB:-16}" \
    LATENCY_MS="${KURA_E2E_THROUGHPUT_LATENCY_MS:-50}" \
    MIN_SPEEDUP="${KURA_E2E_THROUGHPUT_MIN_SPEEDUP:-4}" \
      bash "$(throughput_dir)/run.sh" 2>&1
  }

  It 'uploads markedly faster with the patched nginx window under WAN latency'
    Skip if "set KURA_E2E_THROUGHPUT=1 to run (builds a Go image, ~30-60s)" \
      [ "${KURA_E2E_THROUGHPUT:-0}" != "1" ]

    When call run_throughput
    The status should be success
    The output should include "PASS:"
  End
End
