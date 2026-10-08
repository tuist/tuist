# shellcheck shell=bash

Describe 'Local serving-authority qualification'
  qualification_disabled() { [ "${KURA_E2E_AUTHORITY_RESOURCES:-0}" != 1 ]; }
  run_resource_case() {
    node "test/e2e/serving-authority/$1.mjs" "$KURA_E2E_AUTHORITY_IMAGE" "$KURA_E2E_AUTHORITY_OUTPUT/$1"
  }

  It 'fences an expired frozen runtime and refuses its dirty restart'
    Skip if 'requires KURA_E2E_AUTHORITY_RESOURCES=1 and a local candidate image' qualification_disabled
    When call run_resource_case pause
    The status should be success
    The output should include '"lateWriteAbsent":true'
  End

  It 'rejects an incomplete corpus under disk pressure and recovers after space is restored'
    Skip if 'requires KURA_E2E_AUTHORITY_RESOURCES=1 and an 8 GiB Docker VM' qualification_disabled
    When call run_resource_case pressure
    The status should be success
    The output should include '"incompleteHandoverRejected":true'
  End
End
