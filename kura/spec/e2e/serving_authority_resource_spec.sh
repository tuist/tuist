# shellcheck shell=bash

Describe 'Local serving-authority qualification'
  qualification_disabled() { [ "${KURA_E2E_AUTHORITY_RESOURCES:-0}" != 1 ]; }
  run_resource_case() {
    node "test/e2e/serving-authority/$1.mjs" "$KURA_E2E_AUTHORITY_IMAGE" "$KURA_E2E_AUTHORITY_OUTPUT/$1"
  }
  run_retained_recency_case() {
    KURA_E2E_SEGMENT_RECORDS=2048 KURA_E2E_RETAINED_RECENCY=1 \
      node test/e2e/serving-authority/segmented-handover.mjs "$KURA_E2E_AUTHORITY_IMAGE" "$KURA_E2E_AUTHORITY_OUTPUT/retained-recency"
  }

  It 'preserves inline metadata through individual fetches and retained-corpus handover'
    Skip if 'requires KURA_E2E_AUTHORITY_RESOURCES=1 and a local candidate image' qualification_disabled
    When call run_resource_case inline-handover
    The status should be success
    The output should include '"individualInlineHandover":true'
  End

  It 'preserves a segmented corpus through retained-corpus handover'
    Skip if 'requires KURA_E2E_AUTHORITY_RESOURCES=1 and a local candidate image' qualification_disabled
    When call run_resource_case segmented-handover
    The status should be success
    The output should include '"segmentedHandover":true'
  End

  It 'repairs an old missing retained record on a full standby without increasing capacity'
    Skip if 'requires KURA_E2E_AUTHORITY_RESOURCES=1 and a local candidate image' qualification_disabled
    When call run_retained_recency_case
    The status should be success
    The output should include '"segmentedHandover":true'
  End

  It 'fences an expired frozen runtime and refuses its dirty restart'
    Skip if 'requires KURA_E2E_AUTHORITY_RESOURCES=1 and a local candidate image' qualification_disabled
    When call run_resource_case pause
    The status should be success
    The output should include '"lateWriteAbsent":true'
  End

  It 'resumes only the same live writer after explicit fencing and drained uploads'
    Skip if 'requires KURA_E2E_AUTHORITY_RESOURCES=1 and a local candidate image' qualification_disabled
    When call run_resource_case resume
    The status should be success
    The output should include '"sameWriterResumed":true'
  End

  It 'rejects an incomplete corpus under disk pressure and recovers after space is restored'
    Skip if 'requires KURA_E2E_AUTHORITY_RESOURCES=1 and an 8 GiB Docker VM' qualification_disabled
    When call run_resource_case pressure
    The status should be success
    The output should include '"incompleteHandoverRejected":true'
  End
End
