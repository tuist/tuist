# shellcheck shell=bash

Describe 'actively supported protocol interoperability'
  Include spec/e2e/support.sh

  greater_than() { [ "${greater_than:?}" -gt "$1" ]; }

  setup_suite() {
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-clients
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us kura-eu kura-ap || return 1

    resolve_http_node KURA_US kura-us
    resolve_http_node KURA_EU kura-eu
    resolve_http_node KURA_AP kura-ap
    # Bazel/Buck REAPI runs over the single co-hosted HTTP + h2c gRPC listener
    # (4000), the same port the cache clients above use.
    KURA_US_CACHE_PORT="$(resolve_host_port kura-us 4000)"
    KURA_EU_CACHE_PORT="$(resolve_host_port kura-eu 4000)"
    KURA_AP_CACHE_PORT="$(resolve_host_port kura-ap 4000)"

    wait_for_http "${KURA_US_URL}/up"
    wait_for_http "${KURA_EU_URL}/up"
    wait_for_http "${KURA_AP_URL}/up"
    capture_into us_up wait_for_contains "${KURA_US_URL}/status/cluster" '"ring_members":3' || return 1
    capture_into eu_up wait_for_contains "${KURA_EU_URL}/status/cluster" '"ring_members":3' || return 1
    capture_into ap_up wait_for_contains "${KURA_AP_URL}/status/cluster" '"ring_members":3' || return 1
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

  It 'reads chunked module and Gradle uploads through legacy routes across regions'
    When run python3 "${PROJECT_ROOT}/test/e2e/chunked_upload_probe.py" "$KURA_US_URL" "$KURA_EU_URL"
    The status should be success
    The output should include 'module: negotiated upload'
    The output should include 'gradle: negotiated upload'
  End

  It 'reuses Bazel remote cache entries across regions'
    marker="bazel-$(new_marker)"
    instance_name="bazel/${marker}"
    work1="$(mktemp -d "${SUITE_TMP_DIR}/bazel-1.XXXXXX")"

    create_bazel_workspace "$work1" "$marker"
    capture_into first_build bazel_build "$work1" "$KURA_US_CACHE_PORT" "$instance_name" || return 1
    first_artifact="$(cat "$work1/bazel-bin/hello.txt")"
    The variable first_build should not include 'remote cache hit'
    The variable first_artifact should include "${marker}"

    second_build=""
    second_artifact=""
    for attempt in $(seq 1 10); do
      work2="$(mktemp -d "${SUITE_TMP_DIR}/bazel-2.${attempt}.XXXXXX")"
      create_bazel_workspace "$work2" "$marker"
      capture_into second_build bazel_build "$work2" "$KURA_EU_CACHE_PORT" "$instance_name" || return 1
      second_artifact="$(cat "$work2/bazel-bin/hello.txt")"
      if [[ "${second_build}" == *'remote cache hit'* ]]; then
        break
      fi
      sleep 1
    done

    The variable second_build should include 'remote cache hit'
    The variable second_artifact should include "${marker}"
  End

  It 'advertises and exercises content-defined chunking with Bazel'
    marker="chunking-$(new_marker)"
    instance_name="bazel/${marker}"
    work1="$(mktemp -d "${SUITE_TMP_DIR}/bazel-chunking-1.XXXXXX")"
    splice_route='route="/build.bazel.remote.execution.v2.ContentAddressableStorage/SpliceBlob"'
    split_route='route="/build.bazel.remote.execution.v2.ContentAddressableStorage/SplitBlob"'
    splice_before="$(metric_sum "$KURA_US_URL" kura_public_request_latency_seconds_count "$splice_route")"
    split_before="$(metric_sum "$KURA_EU_URL" kura_public_request_latency_seconds_count "$split_route")"

    create_chunked_bazel_workspace "$work1" "$marker"
    capture_into first_build bazel_build_chunked "$work1" "$KURA_US_CACHE_PORT" "$instance_name" || return 1
    first_size="$(wc -c <"$work1/bazel-bin/large-output.bin" | tr -d ' ')"
    splice_after="$(metric_sum "$KURA_US_URL" kura_public_request_latency_seconds_count "$splice_route")"

    second_build=""
    second_size=""
    for attempt in $(seq 1 10); do
      work2="$(mktemp -d "${SUITE_TMP_DIR}/bazel-chunking-2.${attempt}.XXXXXX")"
      create_chunked_bazel_workspace "$work2" "$marker"
      capture_into second_build bazel_build_chunked "$work2" "$KURA_EU_CACHE_PORT" "$instance_name" false || return 1
      second_size="$(wc -c <"$work2/bazel-bin/large-output.bin" | tr -d ' ')"
      if [[ "${second_build}" == *'remote cache hit'* ]]; then
        break
      fi
      sleep 1
    done
    split_after="$(metric_sum "$KURA_EU_URL" kura_public_request_latency_seconds_count "$split_route")"

    The variable first_build should not include 'remote cache hit'
    The value "$first_size" should equal $((8 * 1024 * 1024 + ${#marker}))
    The variable second_build should include 'remote cache hit'
    The value "$second_size" should equal "$first_size"
    The value "$splice_after" should satisfy greater_than "$splice_before"
    The value "$split_after" should satisfy greater_than "$split_before"
  End

  It 'builds Buck2 targets against the REAPI surface in multiple regions'
    marker="buck-$(new_marker)"
    instance_name="buck/${marker}"
    work1="$(mktemp -d "${SUITE_TMP_DIR}/buck-1.XXXXXX")"
    work2="$(mktemp -d "${SUITE_TMP_DIR}/buck-2.XXXXXX")"

    create_buck_workspace "$work1" "$KURA_US_CACHE_PORT" "$marker" "$instance_name"
    capture_into first_build buck_build "$work1" "buck-${marker}-us" || return 1
    first_output_path="$(printf '%s\n' "$first_build" | awk '/^root\/\/:hello_world / { print $2 }' | tail -n1)"
    The value "${first_output_path}" should be present
    first_output_body="$(cat "$work1/$first_output_path")"
    The variable first_build should include 'Cache hits: 0%'
    The variable first_output_body should include "${marker}"

    create_buck_workspace "$work2" "$KURA_EU_CACHE_PORT" "$marker" "$instance_name"
    capture_into second_build buck_build "$work2" "buck-${marker}-eu" || return 1
    second_output_path="$(printf '%s\n' "$second_build" | awk '/^root\/\/:hello_world / { print $2 }' | tail -n1)"
    The value "${second_output_path}" should be present
    second_output_body="$(cat "$work2/$second_output_path")"
    The variable second_build should include 'BUILD SUCCEEDED'
    The variable second_output_body should include "${marker}"
  End

End
