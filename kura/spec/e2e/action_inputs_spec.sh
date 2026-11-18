# shellcheck shell=bash

# GetTree and the x-tuist-action-inputs batch read, which the remote execution
# gateway uses to prefetch an action's inputs, against a real node over the
# network. The harness lives in test/e2e/action-inputs/.
Describe 'REAPI action input reads'
  run_action_inputs() {
    bash "${KURA_PROJECT_ROOT:?missing KURA_PROJECT_ROOT}/test/e2e/action-inputs/run.sh" 2>&1
  }

  It 'returns an input tree and an action with its inputs in walk order'
    When call run_action_inputs
    The status should be success
    The output should include "PASS:"
  End
End
