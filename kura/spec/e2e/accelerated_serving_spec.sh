# shellcheck shell=bash

Describe 'accelerated artifact serving'
  Include spec/e2e/support.sh

  setup_suite() {
    # Exercises the accelerator on the COMBINED port like the rest of the suite:
    # kura routes the combined listener through the same accelerated server, so
    # HTTP/1.1 artifact GETs hit the sendfile fast path while gRPC co-hosts on
    # the same port. No dedicated-port override needed.
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    setup_suite_tmpdir

    suite_env COMPOSE_PROJECT_NAME kura-accelerated
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

  # The compose nodes run KURA_TENANT_ID=default with accelerated file serving at
  # its default (enabled), so a same-tenant file-backed GET on Linux is served by
  # the same-port accelerator rather than the Axum fallback. This guards that the
  # accelerator keeps the connection alive instead of forcing connection: close.
  It 'serves sequential downloads of a file-backed artifact over one reused connection'
    marker="$(new_marker)"
    artifact_id="accelerated-${marker}"
    url="${KURA_US_URL}/api/cache/cas/${artifact_id}?tenant_id=default"

    payload="${SUITE_TMP_DIR}/payload-${marker}.bin"
    # 256 KiB keeps the artifact file-backed (CAS uploads are never inline) and
    # large enough to exercise a real accelerated transfer.
    head -c 262144 /dev/urandom >"${payload}"

    put_status="$(status_only -X POST "${url}" \
      -H "content-type: application/octet-stream" \
      --data-binary "@${payload}")"
    The variable put_status should eq 204

    capture_into ready_status wait_for_status "${url}" 200 || return 1
    The variable ready_status should eq 200

    out1="${SUITE_TMP_DIR}/out1-${marker}.bin"
    out2="${SUITE_TMP_DIR}/out2-${marker}.bin"
    trace="${SUITE_TMP_DIR}/curl-${marker}.log"

    # Two sequential GETs in a single curl invocation over HTTP/1.1: the second
    # request must reuse the connection the accelerator kept open.
    curl -sS -v --http1.1 \
      -o "${out1}" "${url}" \
      -o "${out2}" "${url}" \
      >/dev/null 2>"${trace}"

    reused="$(grep -c 'Re-using existing connection' "${trace}" || true)"
    if [ "${reused:-0}" -ge 1 ]; then reused_connection=yes; else reused_connection=no; fi
    The variable reused_connection should eq "yes"

    first_match="$(cmp -s "${payload}" "${out1}" && echo match || echo differ)"
    second_match="$(cmp -s "${payload}" "${out2}" && echo match || echo differ)"
    The variable first_match should eq "match"
    The variable second_match should eq "match"
  End
End
