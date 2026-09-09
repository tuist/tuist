# shellcheck shell=bash

Describe 'memory-derived multipart admission'
  Include spec/e2e/support.sh

  setup_suite() {
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    setup_suite_tmpdir
    suite_env COMPOSE_PROJECT_NAME kura-multipart-admission
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
  Before 'resolve_http_node KURA_US kura-us'
  AfterAll 'teardown_suite'

  It 'admits more than 128 sessions and sheds at its memory-derived limit'
    # Compose gives this node 256 MiB between the soft and hard watermarks.
    capture_into metrics wait_for_contains "${KURA_US_URL}/metrics" \
      'kura_multipart_upload_capacity 256' || return 1
    The variable metrics should include 'kura_multipart_upload_capacity 256'

    admitted=0
    for index in $(seq 1 257); do
      response="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=burst-${index}&name=Module&cache_category=builds")"
      if [ "${response}" != 200 ]; then
        break
      fi
      admitted=$((admitted + 1))
    done
    The variable admitted should eq 256
    The variable response should eq 429

    capture_into metrics wait_for_contains "${KURA_US_URL}/metrics" \
      'kura_multipart_uploads 256' || return 1
    The variable metrics should include 'kura_multipart_uploads 256'
    The variable metrics should include 'kura_multipart_upload_capacity 256'
  End
End
