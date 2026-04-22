# shellcheck shell=bash

Describe 'client protocol interoperability'
  Include spec/e2e/support.sh

  setup_suite() {
    export COMPOSE_PROJECT_NAME="kura-clients"
    export KURA_US_PORT=4401
    export KURA_EU_PORT=4402
    export KURA_AP_PORT=4403
    export KURA_US_GRPC_PORT=5501
    export KURA_EU_GRPC_PORT=5502
    export KURA_AP_GRPC_PORT=5503
    export KURA_US_URL="http://localhost:${KURA_US_PORT}"
    export KURA_EU_URL="http://localhost:${KURA_EU_PORT}"
    export KURA_AP_URL="http://localhost:${KURA_AP_PORT}"

    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    setup_suite_tmpdir

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    dc up --build -d kura-us kura-eu kura-ap >/dev/null 2>&1

    wait_for_http "${KURA_US_URL}/up"
    wait_for_http "${KURA_EU_URL}/up"
    wait_for_http "${KURA_AP_URL}/up"
    capture_into us_up wait_for_contains "${KURA_US_URL}/up" '"ring_members":3' || return 1
    capture_into eu_up wait_for_contains "${KURA_EU_URL}/up" '"ring_members":3' || return 1
    capture_into ap_up wait_for_contains "${KURA_AP_URL}/up" '"ring_members":3' || return 1
    [[ "${us_up}" == *'"ring_members":3'* ]]
    [[ "${eu_up}" == *'"ring_members":3'* ]]
    [[ "${ap_up}" == *'"ring_members":3'* ]]
  }

  teardown_suite() {
    kill_buck2
    kill_bazel_servers
    dc down -v --remove-orphans >/dev/null 2>&1 || true
    if [ -n "${SUITE_TMP_DIR:-}" ] && [ -d "${SUITE_TMP_DIR}" ]; then
      rm -rf "${SUITE_TMP_DIR}"
    fi
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  It 'reuses Bazel remote cache entries across regions'
    marker="bazel-$(new_marker)"
    instance_name="bazel/${marker}"
    work1="$(mktemp -d "${SUITE_TMP_DIR}/bazel-1.XXXXXX")"

    create_bazel_workspace "$work1" "$marker"
    capture_into first_build bazel_build "$work1" "$KURA_US_GRPC_PORT" "$instance_name" || return 1
    first_artifact="$(cat "$work1/bazel-bin/hello.txt")"
    The variable first_build should not include 'remote cache hit'
    The variable first_artifact should include "${marker}"

    second_build=""
    second_artifact=""
    for attempt in $(seq 1 10); do
      work2="$(mktemp -d "${SUITE_TMP_DIR}/bazel-2.${attempt}.XXXXXX")"
      create_bazel_workspace "$work2" "$marker"
      capture_into second_build bazel_build "$work2" "$KURA_EU_GRPC_PORT" "$instance_name" || return 1
      second_artifact="$(cat "$work2/bazel-bin/hello.txt")"
      if [[ "${second_build}" == *'remote cache hit'* ]]; then
        break
      fi
      sleep 1
    done

    The variable second_build should include 'remote cache hit'
    The variable second_artifact should include "${marker}"
  End

  It 'builds Buck2 targets against the REAPI surface in multiple regions'
    marker="buck-$(new_marker)"
    instance_name="buck/${marker}"
    work1="$(mktemp -d "${SUITE_TMP_DIR}/buck-1.XXXXXX")"
    work2="$(mktemp -d "${SUITE_TMP_DIR}/buck-2.XXXXXX")"

    create_buck_workspace "$work1" "$KURA_US_GRPC_PORT" "$marker" "$instance_name"
    capture_into first_build buck_build "$work1" "buck-${marker}-us" || return 1
    first_output_path="$(printf '%s\n' "$first_build" | awk '/^root\/\/:hello_world / { print $2 }' | tail -n1)"
    The value "${first_output_path}" should be present
    first_output_body="$(cat "$work1/$first_output_path")"
    The variable first_build should include 'Cache hits: 0%'
    The variable first_output_body should include "${marker}"

    create_buck_workspace "$work2" "$KURA_EU_GRPC_PORT" "$marker" "$instance_name"
    capture_into second_build buck_build "$work2" "buck-${marker}-eu" || return 1
    second_output_path="$(printf '%s\n' "$second_build" | awk '/^root\/\/:hello_world / { print $2 }' | tail -n1)"
    The value "${second_output_path}" should be present
    second_output_body="$(cat "$work2/$second_output_path")"
    The variable second_build should include 'BUILD SUCCEEDED'
    The variable second_output_body should include "${marker}"
  End

  It 'replicates Nx self-hosted cache entries across regions'
    marker="nx-$(new_marker)"
    work1="$(mktemp -d "${SUITE_TMP_DIR}/nx-1.XXXXXX")"

    create_nx_workspace "$work1" "$marker"
    capture_into first_build nx_build "$work1" "${KURA_US_URL}" || return 1
    first_output="$(cat "$work1/dist/apps/demo/out.txt")"
    The variable first_build should not include '[remote cache]'
    The variable first_output should include "${marker}"

    second_build=""
    second_output=""
    for attempt in $(seq 1 10); do
      work2="$(mktemp -d "${SUITE_TMP_DIR}/nx-2.${attempt}.XXXXXX")"
      cp -R "$work1/." "$work2/"
      rm -rf "$work2/.nx" "$work2/dist"
      capture_into second_build nx_build "$work2" "${KURA_EU_URL}" || return 1
      second_output="$(cat "$work2/dist/apps/demo/out.txt")"
      if [[ "${second_build}" == *'[remote cache]'* ]]; then
        break
      fi
      sleep 1
    done

    The variable second_build should include '[remote cache]'
    The variable second_output should include "${marker}"
  End

  It 'syncs Metro cache artifacts across regions'
    work="$(mktemp -d "${SUITE_TMP_DIR}/metro.XXXXXX")"
    key_hex="$(new_marker)$(new_marker)"
    payload="metro-$(new_marker)"

    create_metro_workspace "$work"
    metro_put "$work" "${KURA_US_URL}/api/metro/cache" "$key_hex" "$payload" || return 1

    metro_body=""
    for _ in $(seq 1 20); do
      if capture_into metro_body metro_get "$work" "${KURA_EU_URL}/api/metro/cache" "$key_hex"; then
        break
      fi
      sleep 1
    done

    The variable metro_body should eq "${payload}"
  End
End
