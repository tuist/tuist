# shellcheck shell=bash

Describe 'upload body failure classification'
  Include spec/e2e/support.sh

  setup_suite() {
    setup_suite_tmpdir
    if [ -n "${KURA_UPLOAD_TEST_URL:-}" ]; then
      KURA_US_URL="${KURA_UPLOAD_TEST_URL}"
      return 0
    fi
    COMPOSE_FILES=(-f "${PROJECT_ROOT}/docker-compose.yml")
    suite_env COMPOSE_PROJECT_NAME kura-upload-errors
    ephemeral_ports KURA_US_PORT
    dc down -v --remove-orphans >/dev/null 2>&1 || true
    compose_up kura-us || return 1
    resolve_http_node KURA_US kura-us
    wait_for_http "${KURA_US_URL}/up"
  }

  teardown_suite() {
    if [ -n "${KURA_UPLOAD_TEST_URL:-}" ]; then
      rm -rf "${SUITE_TMP_DIR:?}"
    else
      compose_teardown
    fi
  }

  BeforeAll 'setup_suite'
  AfterAll 'teardown_suite'

  check_failed_upload() {
    python3 - "${KURA_US_URL}" "$1" "${2:-cas}" <<'PY'
import json
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

base, mode, protocol = sys.argv[1:]
address = urllib.parse.urlsplit(base)
assert address.scheme == 'http' and address.hostname in ('localhost', '127.0.0.1', '::1')
query = '?tenant_id=default&namespace_id=' + uuid.uuid4().hex
if protocol == 'cas':
    path = '/api/cache/cas/upload-fault' + query
    read_path, method, route = path, 'POST', '/api/cache/cas/{id}'
else:
    path = '/api/cache/keyvalue' + query
    read_path, method, route = '/api/cache/keyvalue/upload-fault' + query, 'PUT', '/api/cache/keyvalue'

expected = '499' if mode == 'truncated' else '400'

def counters():
    with urllib.request.urlopen(base + '/metrics', timeout=5) as response:
        lines = response.read().decode().splitlines()
    result = {}
    for line in lines:
        if line.startswith('kura_http_requests_total_total{') and f'route="{route}"' in line:
            status = re.search(r'status="(\d+)"', line).group(1)
            result[status] = result.get(status, 0) + float(line.rsplit(' ', 1)[1])
        if line.startswith('kura_artifact_writes_total_total{') and 'result="error"' in line:
            result['write_errors'] = result.get('write_errors', 0) + float(line.rsplit(' ', 1)[1])
    return result

before = counters()
if mode == 'truncated':
    framing, payload = 'Content-Length: 100\r\n', b'partial'
else:
    framing, payload = 'Transfer-Encoding: chunked\r\n', b'7\r\npartial\r\nZ\r\n'
with socket.create_connection((address.hostname, address.port), timeout=5) as connection:
    connection.sendall((f'{method} {path} HTTP/1.1\r\nHost: localhost\r\n{framing}\r\n').encode() + payload)
    connection.shutdown(socket.SHUT_WR)
    try:
        while connection.recv(4096):
            pass
    except ConnectionResetError:
        pass

deadline = time.monotonic() + 5
while True:
    after = counters()
    if after.get(expected, 0) == before.get(expected, 0) + 1:
        break
    assert time.monotonic() < deadline, (mode, before, after)
    time.sleep(0.05)
assert after.get('write_errors', 0) == before.get('write_errors', 0) + 1
assert sum(v for k, v in after.items() if k.startswith('5')) == sum(v for k, v in before.items() if k.startswith('5'))
try:
    urllib.request.urlopen(base + read_path, timeout=5)
    raise AssertionError('partial artifact was published')
except urllib.error.HTTPError as error:
    assert error.code == 404

payload = b'complete retry after rejected upload'
expected_body = payload
if protocol == 'keyvalue':
    entry = {'entries': [{'value': 'complete retry after rejected upload'}]}
    payload = json.dumps(dict(cas_id='upload-fault', **entry)).encode()
request = urllib.request.Request(base + path, data=payload, method=method)
with urllib.request.urlopen(request, timeout=5) as response:
    assert response.status == 204
with urllib.request.urlopen(base + read_path, timeout=5) as response:
    data = response.read()
    if protocol == 'keyvalue':
        assert json.loads(data) == entry
    else:
        assert data == expected_body
print('classified, rejected partial artifact, and recovered on retry')
PY
  }

  It 'records a premature upload EOF as 499 and accepts a complete retry'
    When call check_failed_upload truncated
    The status should be success
    The output should eq 'classified, rejected partial artifact, and recovered on retry'
  End

  It 'records malformed chunk framing as 400 and accepts a complete retry'
    When call check_failed_upload malformed
    The status should be success
    The output should eq 'classified, rejected partial artifact, and recovered on retry'
  End

  It 'classifies an interrupted inline key-value upload and accepts a complete retry'
    When call check_failed_upload truncated keyvalue
    The status should be success
    The output should eq 'classified, rejected partial artifact, and recovered on retry'
  End

  It 'classifies malformed inline framing and accepts a complete retry'
    When call check_failed_upload malformed keyvalue
    The status should be success
    The output should eq 'classified, rejected partial artifact, and recovered on retry'
  End
End
