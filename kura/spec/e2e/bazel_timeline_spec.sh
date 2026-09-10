# shellcheck shell=bash

Describe 'Bazel timelines through Kura and the Tuist server'
  Skip if 'local timeline endpoints and a project token are not configured' test -z "${TUIST_TIMELINE_TOKEN_FILE:-}"

  setup_timeline() {
    timeline_dir="$(mktemp -d)" || return 1
    printf '9.1.1\n' > "$timeline_dir/.bazelversion"
    cat > "$timeline_dir/MODULE.bazel" <<'MODULE'
module(name = "timeline_verification")
bazel_dep(name = "rules_cc", version = "0.2.19")
MODULE
    cat > "$timeline_dir/BUILD.bazel" <<'BUILD'
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
cc_binary(name = "app", srcs = glob(["src/*.cc"]))
cc_binary(name = "broken", srcs = ["broken.cc"])
BUILD
    mkdir "$timeline_dir/src"
    for i in $(seq 1 64); do
      printf 'int function_%s(int n) { return n + %s; }\n' "$i" "$i" > "$timeline_dir/src/part${i}.cc"
    done
    printf 'int main() { return 0; }\n' > "$timeline_dir/src/main.cc"
    printf '#error Timeline_compiler_diagnostic\n' > "$timeline_dir/broken.cc"
  }

  cleanup_timeline() {
    if [ -n "${timeline_dir:-}" ]; then
      (cd "$timeline_dir" && bazel --output_user_root="$timeline_dir/output" shutdown) >/dev/null 2>&1 || true
      rm -rf "$timeline_dir"
    fi
  }

  BeforeAll 'setup_timeline'
  AfterAll 'cleanup_timeline'

  build_timeline() {
    local target="$1" invocation="$2" token
    token="$(cat "$TUIST_TIMELINE_TOKEN_FILE")"
    (cd "$timeline_dir" && bazel --output_user_root="$timeline_dir/output" build "$target" \
      --invocation_id="$invocation" \
      --bes_backend="$TUIST_TIMELINE_KURA_URL" --remote_cache="$TUIST_TIMELINE_KURA_URL" \
      --bes_header="authorization=Bearer $token" --remote_header="authorization=Bearer $token" \
      --bes_header="x-tuist-account-handle=${TUIST_TIMELINE_PROJECT%/*}" \
      --bes_header="x-tuist-project-handle=${TUIST_TIMELINE_PROJECT#*/}" \
      --remote_header="x-tuist-account-handle=${TUIST_TIMELINE_PROJECT%/*}" \
      --remote_instance_name="${TUIST_TIMELINE_PROJECT#*/}" \
      --bes_upload_mode=wait_for_upload_complete --build_event_publish_all_actions \
      --generate_json_trace_profile=yes --noslim_profile \
      --experimental_profile_include_target_label --experimental_profile_include_primary_output \
      --experimental_build_event_upload_strategy=remote --noremote_accept_cached) > "$timeline_dir/$invocation.log" 2>&1
  }

  verify_timeline() {
    local success_id failure_id
    success_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
    failure_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
    build_timeline //:app "$success_id" || return 1
    if build_timeline //:broken "$failure_id"; then return 1; fi
    python3 - "$success_id" "$failure_id" "$timeline_dir/output" <<'PY'
import collections, gzip, json, os, pathlib, sys, time, urllib.request
success, failure, output = sys.argv[1:]
base = os.environ['TUIST_TIMELINE_SERVER_URL'] + '/api/projects/' + os.environ['TUIST_TIMELINE_PROJECT'] + '/bazel/invocations/'
token = pathlib.Path(os.environ['TUIST_TIMELINE_TOKEN_FILE']).read_text().strip()
def get(path):
    req = urllib.request.Request(base + path, headers={'Authorization': 'Bearer ' + token})
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.load(response)
def ready(invocation):
    for attempt in range(30):
        try:
            data = get(invocation + '/steps?page_size=100')
            if data['coverage'] == 'trace_profile':
                return data
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
        time.sleep(1)
    raise AssertionError('The complete profile was not delivered')
data = ready(success)
steps = data['steps']
for page in range(2, data['pagination_metadata']['total_pages'] + 1):
    steps += get(success + '/steps?page_size=100&page=' + str(page))['steps']
profile = next(pathlib.Path(output).glob('*/command-' + success + '.profile.gz'))
raw = json.loads(gzip.open(profile).read())['traceEvents']
expected = {'profile:' + str(i): event for i, event in enumerate(raw)
            if event.get('ph') == 'X' and event.get('dur', 0) > 0 and event.get('ts', -1) >= 0}
assert len(steps) == len(expected)
assert sum(step['category'] == 'CppCompile' for step in steps) == 65
for step in steps:
    event = expected[step['id']]
    assert step['start_ms'] == event['ts'] / 1000
    assert step['duration_ms'] == event['dur'] / 1000
assert any(event.get('name') == 'CPU usage (total)' for event in raw)
ready(failure)
failed = get(failure + '/steps?status=failure')['steps']
assert failed
assert any('Timeline_compiler_diagnostic' in (get(failure + '/steps/' + step['id'])['log'] or '') for step in failed)
if os.environ.get('TUIST_TIMELINE_EVIDENCE_FILE'):
    evidence = pathlib.Path(os.environ['TUIST_TIMELINE_EVIDENCE_FILE'])
    evidence.write_text(json.dumps({'success': success, 'failure': failure, 'steps': len(steps),
        'compilations': 65, 'counters': dict(collections.Counter(e['name'] for e in raw if e.get('ph') == 'C'))}, indent=2))
    evidence.with_suffix('.profile.gz').write_bytes(profile.read_bytes())
print('Verified all profile intervals, 65 compiler actions, native CPU samples and the failed action log')
PY
  }

  It 'delivers every profile interval and correlates real compiler diagnostics'
    When call verify_timeline
    The status should be success
    The output should include 'Verified all profile intervals'
  End

End
