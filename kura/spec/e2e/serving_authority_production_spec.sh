# shellcheck shell=bash

Describe 'Production-shaped serving-authority qualification'
  production_qualification_disabled() { [ "${KURA_E2E_AUTHORITY_PRODUCTION:-0}" != 1 ]; }
  run_production_case() {
    node test/e2e/serving-authority/production/staging.mjs \
      --context "$KURA_E2E_PRODUCTION_CONTEXT" \
      --namespace "$KURA_E2E_PRODUCTION_NAMESPACE" \
      --node "$KURA_E2E_PRODUCTION_NODE" \
      --output "$KURA_E2E_PRODUCTION_OUTPUT" \
      --profile production \
      --scenario "$KURA_E2E_PRODUCTION_SCENARIO" \
      --source-image "$KURA_E2E_PRODUCTION_SOURCE_IMAGE" \
      --warm-image "$KURA_E2E_PRODUCTION_WARM_IMAGE" \
      --candidate-image "$KURA_E2E_PRODUCTION_CANDIDATE_IMAGE" \
      --expect pass
  }

  It 'hands over a production-shaped retained corpus on a reused standby volume'
    Skip if 'requires explicit isolated staging capacity and KURA_E2E_AUTHORITY_PRODUCTION=1' production_qualification_disabled
    When call run_production_case
    The status should be success
    The output should include '"classification":"pass"'
  End
End
