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

    capture_into first_start curl -fsS -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=first&name=Module&cache_category=builds" || return 1
    first_id="$(extract_upload_id "${first_start}")"
    first_part="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/part?upload_id=${first_id}&part_number=1" \
      --data-binary 'payload')"
    The variable first_part should eq 204
    admitted=1
    for index in $(seq 2 256); do
      response="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=burst-${index}&name=Module&cache_category=builds")"
      if [ "${response}" != 200 ]; then
        break
      fi
      admitted=$((admitted + 1))
    done
    The variable admitted should eq 256
    saturated="$(curl -sS -o /dev/null -w '%{http_code} %{time_total}' -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=saturated&name=Module&cache_category=builds")"
    bounded_timeout="$(printf '%s' "${saturated}" | awk '{print ($1 == 429 && $2 >= 0.9 && $2 < 5) ? "yes" : "no"}')"
    The variable bounded_timeout should eq yes

    curl -sS -o "${SUITE_TMP_DIR}/waiting.json" -w '%{http_code}' -X POST \
      "${KURA_US_URL}/api/cache/module/start?tenant_id=acme&namespace_id=ios&hash=waiting&name=Module&cache_category=builds" \
      >"${SUITE_TMP_DIR}/waiting.status" &
    waiting_pid=$!
    # Observe queue registration before releasing the occupied slot.
    for _ in $(seq 1 50); do
      actions="$(curl -fsS "${KURA_US_URL}/metrics")"
      case "${actions}" in
        *'kura_memory_actions_total_total{action="multipart_upload_admission_wait"} 2'*) break ;;
      esac
      sleep 0.01
    done
    The variable actions should include 'kura_memory_actions_total_total{action="multipart_upload_admission_wait"} 2'
    completed="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/complete?upload_id=${first_id}" \
      -H 'content-type: application/json' -d '{"parts":[1]}')"
    The variable completed should eq 204
    wait "${waiting_pid}"
    waiting_status="$(cat "${SUITE_TMP_DIR}/waiting.status")"
    The variable waiting_status should eq 200
    waiting_id="$(extract_upload_id "$(cat "${SUITE_TMP_DIR}/waiting.json")")"
    The variable waiting_id should be present

    capture_into metrics wait_for_contains "${KURA_US_URL}/metrics" \
      'kura_multipart_uploads 256' || return 1
    The variable metrics should include 'kura_multipart_uploads 256'
    The variable metrics should include 'kura_multipart_upload_capacity 256'
  End
End
