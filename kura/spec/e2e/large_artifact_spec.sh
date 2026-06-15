# shellcheck shell=bash

Describe 'module artifact larger than the segment size'
  Include spec/e2e/support.sh

  resolve_endpoints() {
    resolve_http_node KURA_US kura-us
    resolve_http_node KURA_EU kura-eu
    resolve_http_node KURA_AP kura-ap
  }

  setup_suite() {
    # The override disables the replication bandwidth limiter: this suite checks
    # replication correctness, not production rate-shaping, and the limiter's
    # latency-pressure throttle otherwise starves the >512 MiB transfer past the
    # peer client's fixed 30s timeout (tuist/tuist#11297).
    COMPOSE_FILES=(
      -f "${PROJECT_ROOT}/docker-compose.yml"
      -f "${PROJECT_ROOT}/spec/e2e/docker-compose.large-artifact.yml"
    )
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-large-artifact
    ephemeral_ports KURA_US_PORT KURA_EU_PORT KURA_AP_PORT \
      KURA_US_GRPC_PORT KURA_EU_GRPC_PORT KURA_AP_GRPC_PORT

    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us kura-eu kura-ap || return 1

    resolve_endpoints
    wait_for_http "${KURA_US_URL}/up"
    wait_for_http "${KURA_EU_URL}/up"
    wait_for_http "${KURA_AP_URL}/up"
    capture_into us_up wait_for_contains "${KURA_US_URL}/up" '"ring_members":3' || return 1
    capture_into eu_up wait_for_contains "${KURA_EU_URL}/up" '"ring_members":3' || return 1
    capture_into ap_up wait_for_contains "${KURA_AP_URL}/up" '"ring_members":3' || return 1
  }

  teardown_suite() {
    compose_teardown
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  # A segment caps at MAX_SEGMENT_BYTES = 512 MiB (src/constants.rs), but a single
  # artifact is appended whole and may exceed that ceiling: active_segment rotates
  # to a fresh segment when current_size + incoming_size > MAX_SEGMENT_BYTES and then
  # writes the artifact regardless of its size (src/store.rs). Multipart module uploads
  # (2 GiB cap, 10 MiB per part) are the only client path that can produce such an
  # artifact, and it is far past MAX_INLINE_REPLICATION_BODY_BYTES (4 MiB) so it also
  # rides the streaming peer-replication path (bounded by MAX_REPLICATION_BODY_BYTES =
  # 2 GiB). This drives 520 MiB through that path and asserts a byte-exact round-trip
  # on the origin node AND on both replicas, covering the >segment-size write and
  # replication cases that unit tests cannot reach without real half-gigabyte payloads.
  It 'uploads a 520 MiB module and replicates it byte-for-byte to peer nodes'
    part_bytes=10485760           # 10 MiB == MAX_MODULE_PART_BYTES (max allowed part)
    part_count=52                 # 52 * 10 MiB = 520 MiB > 512 MiB segment ceiling
    total_bytes=$((part_bytes * part_count))

    block="${SUITE_TMP_DIR}/block.bin"
    expected="${SUITE_TMP_DIR}/expected.bin"

    # Generate one random 10 MiB block and stamp it out part_count times. Only 10 MiB
    # of /dev/urandom is read; the 520 MiB expected file is a fast local copy. Reusing
    # the block keeps generation cheap while still moving real (non-sparse) bytes over
    # the wire, so a data-corrupting bug would still fail the cmp checks below.
    dd if=/dev/urandom of="${block}" bs="${part_bytes}" count=1 2>/dev/null
    : >"${expected}"
    for _ in $(seq 1 "${part_count}"); do cat "${block}" >>"${expected}"; done

    nsq="tenant_id=default&namespace_id=ios&hash=large-1&name=Big.framework&cache_category=builds"

    capture_into start_response \
      curl -fsS -X POST "${KURA_US_URL}/api/cache/module/start?${nsq}" || return 1
    upload_id="$(extract_upload_id "${start_response}")"
    The value "${upload_id}" should be present

    upload_failures=0
    for part_number in $(seq 1 "${part_count}"); do
      part_status="$(status_only -X POST \
        "${KURA_US_URL}/api/cache/module/part?upload_id=${upload_id}&part_number=${part_number}" \
        -H "content-type: application/octet-stream" \
        --data-binary "@${block}")"
      if [ "${part_status}" != "204" ]; then
        printf 'part %s failed with status %s\n' "${part_number}" "${part_status}"
        upload_failures=$((upload_failures + 1))
      fi
    done
    The variable upload_failures should eq 0

    # GNU `seq -s,` and BSD `seq -s,` disagree on the trailing separator; `paste`
    # joins without one on both, so the JSON parts array stays valid everywhere.
    parts_json="$(seq 1 "${part_count}" | paste -sd, -)"
    complete_status="$(status_only -X POST \
      "${KURA_US_URL}/api/cache/module/complete?upload_id=${upload_id}" \
      -H "content-type: application/json" \
      -d "{\"parts\":[${parts_json}]}")"
    The variable complete_status should eq 204

    # Origin node: the artifact is served straight from the oversized segment it was
    # just written to.
    us_download="${SUITE_TMP_DIR}/us.bin"
    capture_into us_head wait_for_head_status "${KURA_US_URL}/api/cache/module/x?${nsq}" 204 || return 1
    The variable us_head should eq 204
    us_status="$(curl -sS -o "${us_download}" -w '%{http_code}' "${KURA_US_URL}/api/cache/module/x?${nsq}")"
    The variable us_status should eq 200
    us_bytes="$(wc -c <"${us_download}" | tr -d ' ')"
    The variable us_bytes should eq "${total_bytes}"
    us_integrity="$(cmp -s "${expected}" "${us_download}" && echo match || echo differ)"
    The variable us_integrity should eq match

    # Replica kura-eu: replication is asynchronous (outbox + delivery), so poll HEAD
    # until the artifact lands, then assert the bytes match the origin exactly. The
    # generous attempt budget tolerates slower CI without hanging once it arrives.
    eu_download="${SUITE_TMP_DIR}/eu.bin"
    capture_into eu_head wait_for_head_status "${KURA_EU_URL}/api/cache/module/x?${nsq}" 204 90 2 || return 1
    The variable eu_head should eq 204
    eu_status="$(curl -sS -o "${eu_download}" -w '%{http_code}' "${KURA_EU_URL}/api/cache/module/x?${nsq}")"
    The variable eu_status should eq 200
    eu_bytes="$(wc -c <"${eu_download}" | tr -d ' ')"
    The variable eu_bytes should eq "${total_bytes}"
    eu_integrity="$(cmp -s "${expected}" "${eu_download}" && echo match || echo differ)"
    The variable eu_integrity should eq match

    # Replica kura-ap: same assertion against the third node.
    ap_download="${SUITE_TMP_DIR}/ap.bin"
    capture_into ap_head wait_for_head_status "${KURA_AP_URL}/api/cache/module/x?${nsq}" 204 90 2 || return 1
    The variable ap_head should eq 204
    ap_status="$(curl -sS -o "${ap_download}" -w '%{http_code}' "${KURA_AP_URL}/api/cache/module/x?${nsq}")"
    The variable ap_status should eq 200
    ap_bytes="$(wc -c <"${ap_download}" | tr -d ' ')"
    The variable ap_bytes should eq "${total_bytes}"
    ap_integrity="$(cmp -s "${expected}" "${ap_download}" && echo match || echo differ)"
    The variable ap_integrity should eq match
  End
End
