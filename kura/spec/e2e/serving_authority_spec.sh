# shellcheck shell=bash

Describe 'Isolated managed serving authority'
  authority_disabled() { [ "${KURA_E2E_SERVING_AUTHORITY:-0}" != 1 ]; }
  run_authority() {
    node test/e2e/serving-authority/client.mjs "${KURA_E2E_AUTHORITY_MODE:-handover}" \
      "$KURA_E2E_PRIMARY_URL" "$KURA_E2E_STANDBY_URL" \
      "$KURA_E2E_PRIMARY_POD" "$KURA_E2E_STANDBY_POD"
  }

  It 'preserves handover and controller restarts or rejects expired sessions and writes'
    Skip if 'requires an isolated deployed instance and KURA_E2E_SERVING_AUTHORITY=1' authority_disabled
    When call run_authority
    The status should be success
    The output should include '"mode":'
  End
End
