# shellcheck shell=bash

Describe 'forced memory-pressure simulation'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/spec/e2e/docker-compose.test-pressure.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-forced-pressure
    # Pin the node to sustained constrained pressure: `allow_background_admission`
    # returns false, so the snapshot reconcile's load is denied exactly as it was
    # during the production window that froze the served snapshot.
    suite_env KURA_E2E_FORCE_MEMORY_PRESSURE constrained
    ephemeral_ports KURA_US_PORT

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us || return 1

    resolve_http_node KURA_US kura-us
    wait_for_http "${KURA_US_URL}/up"
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  It 'reports the forced pressure tier and keeps serving under it'
    # The test-only override is the whole point: it pins the node to a
    # deterministic tier so a pressure scenario is reproducible instead of a
    # function of when the kernel happens to reclaim. Constrained == 1.
    metrics="$(curl -fsS "${KURA_US_URL}/metrics")"
    The variable metrics should include 'kura_memory_pressure_state 1'

    # The node must still serve the public cache under sustained pressure — the
    # gate-only snapshot work and the foreground reads share this path, so a
    # crash or a shed here would surface as a build failure, not a stale
    # snapshot.
    artifact_id="artifact-$(new_marker)"
    artifact_path="${SUITE_TMP_DIR}/${artifact_id}.bin"
    cas_url="${KURA_US_URL}/api/cache/cas/${artifact_id}?tenant_id=acme&namespace_id=ios"
    printf 'forced-pressure-payload' >"${artifact_path}"

    put_status="$(status_only -X POST "${cas_url}" \
      -H 'content-type: application/octet-stream' \
      --data-binary "@${artifact_path}")"
    The variable put_status should eq 204

    get_status="$(status_only "${cas_url}")"
    The variable get_status should eq 200

    us_status="$(container_status kura-us)"
    The variable us_status should eq running
    us_restarts="$(container_restart_count kura-us)"
    The variable us_restarts should eq 0
  End
End
