#shellcheck shell=bash
# End-to-end specs for `once exec` (substrate escape hatch).

Describe 'once exec'
  BeforeEach 'setup_workspace'
  AfterEach 'cleanup_workspace'

  It 'executes the command and reports a cache miss on first run'
    When call once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hello'
    The status should be success
    The stdout should equal 'hello'
    The stderr should include 'cache miss'
    The stderr should include 'exit=0'
  End

  It 'returns the cached result on a second identical invocation'
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hi' >/dev/null 2>&1
    When call once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hi'
    The status should be success
    The stdout should equal 'hi'
    The stderr should include 'cache hit'
  End

  It 'does not re-execute the command on a cache hit'
    sentinel="$WORKSPACE/sentinel"
    cmd="touch '$sentinel'"
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c "$cmd" >/dev/null 2>&1
    rm -f "$sentinel"
    When call once exec -e PATH=/usr/bin:/bin -- /bin/sh -c "$cmd"
    The status should be success
    The stderr should include 'cache hit'
    The path "$sentinel" should not be exist
  End

  It 'executes an annotated script file directly through a Once shebang'
    mkdir -p "$WORKSPACE/scripts"
    cat > "$WORKSPACE/scripts/build.sh" <<EOF
#!/usr/bin/env -S $ONCE_BIN exec -- bash
# once input "../input.txt"
# once cwd ".."
cat input.txt
EOF
    chmod +x "$WORKSPACE/scripts/build.sh"
    cat > "$WORKSPACE/input.txt" <<'EOF'
hello direct script
EOF
    When call env PATH=/usr/bin:/bin "$WORKSPACE/scripts/build.sh"
    The status should be success
    The stdout should equal 'hello direct script'
    The stderr should include 'cache miss'
  End

  It 'returns a cache hit when an annotated script file is re-executed directly'
    mkdir -p "$WORKSPACE/scripts"
    cat > "$WORKSPACE/scripts/build.sh" <<EOF
#!/usr/bin/env -S $ONCE_BIN exec -- bash
# once input "../input.txt"
# once cwd ".."
cat input.txt
EOF
    chmod +x "$WORKSPACE/scripts/build.sh"
    cat > "$WORKSPACE/input.txt" <<'EOF'
cached direct script
EOF
    env PATH=/usr/bin:/bin "$WORKSPACE/scripts/build.sh" >/dev/null 2>&1
    When call env PATH=/usr/bin:/bin "$WORKSPACE/scripts/build.sh"
    The status should be success
    The stdout should equal 'cached direct script'
    The stderr should include 'cache hit'
  End

  It 'executes an annotated script file through once exec without --script'
    mkdir -p "$WORKSPACE/scripts"
    cat > "$WORKSPACE/scripts/build.sh" <<'EOF'
#!/usr/bin/env bash
# once input "../input.txt"
# once cwd ".."
cat input.txt
EOF
    cat > "$WORKSPACE/input.txt" <<'EOF'
hello through once exec
EOF
    When call once exec -e PATH=/usr/bin:/bin -- bash scripts/build.sh
    The status should be success
    The stdout should equal 'hello through once exec'
    The stderr should include 'cache miss'
  End

  It 'executes an annotated script file through once exec with --script'
    mkdir -p "$WORKSPACE/scripts"
    cat > "$WORKSPACE/scripts/build.sh" <<'EOF'
#!/usr/bin/env bash
# once input "../input.txt"
# once cwd ".."
cat input.txt
EOF
    cat > "$WORKSPACE/input.txt" <<'EOF'
hello through once exec --script
EOF
    When call once exec --script -e PATH=/usr/bin:/bin -- bash scripts/build.sh
    The status should be success
    The stdout should equal 'hello through once exec --script'
    The stderr should include 'cache miss'
  End

  It 'runs a command through the microsandbox compute provider'
    Skip if 'microsandbox specs are opt-in' microsandbox_specs_disabled
    When call "$ONCE_BIN" -C "$WORKSPACE" exec --remote --compute microsandbox -- /bin/sh -c 'printf remote-output'
    The status should be success
    The stdout should equal 'remote-output'
    The stderr should include 'cache miss'
  End

  It 'runs a command through the daytona compute provider'
    cat > "$WORKSPACE/daytona_api.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import subprocess

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        if self.path != "/toolbox/sandbox-1/process/execute":
            self.send_error(404)
            return
        if self.headers.get("Authorization") != "Bearer token-1":
            self.send_error(401)
            return
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        proc = subprocess.run(
            request["command"],
            shell=True,
            cwd=request["cwd"],
            capture_output=True,
            text=True,
        )
        body = json.dumps({
            "exitCode": proc.returncode,
            "artifacts": {
                "stdout": proc.stdout,
                "stderr": "daytona stderr\n" + proc.stderr,
            },
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_port, flush=True)
server.handle_request()
PY
    python3 "$WORKSPACE/daytona_api.py" > "$WORKSPACE/daytona_port" &
    while [ ! -s "$WORKSPACE/daytona_port" ]; do sleep 0.05; done
    port="$(cat "$WORKSPACE/daytona_port")"
    When call env ONCE_DAYTONA_SANDBOX=sandbox-1 ONCE_DAYTONA_API_URL="http://127.0.0.1:$port" ONCE_DAYTONA_API_KEY=token-1 ONCE_DAYTONA_WORKDIR="$WORKSPACE" "$ONCE_BIN" -C "$WORKSPACE" exec --remote --compute daytona -e VALUE=output -- /bin/sh -c 'printf "daytona-$VALUE"'
    The status should be success
    The stdout should equal 'daytona-output'
    The stderr should include 'daytona stderr'
    The stderr should include 'cache miss'
  End

  It 'propagates the underlying exit code'
    When call once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'exit 7'
    The status should equal 7
    The stderr should include 'exit=7'
  End

  It 'does not cache failing exits by default'
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'exit 3' >/dev/null 2>&1 || true
    When call once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'exit 3'
    The status should equal 3
    # Second run is still a miss; failures are intentionally not
    # written to the cache without --cache-failures.
    The stderr should include 'cache miss'
  End

  It 'caches failing exits when --cache-failures is set'
    once exec --cache-failures -e PATH=/usr/bin:/bin -- /bin/sh -c 'exit 3' >/dev/null 2>&1 || true
    When call once exec --cache-failures -e PATH=/usr/bin:/bin -- /bin/sh -c 'exit 3'
    The status should equal 3
    The stderr should include 'cache hit'
  End

  It 'uses argv as part of the cache key'
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf one' >/dev/null 2>&1
    When call once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf two'
    The status should be success
    The stdout should equal 'two'
    The stderr should include 'cache miss'
  End

  It 'uses env as part of the cache key'
    # printenv reads the env directly without going through a shell;
    # no quoting variability across bash/dash on different runners.
    once exec -e PATH=/usr/bin:/bin -e MODE=a -- /usr/bin/printenv MODE >/dev/null 2>&1
    When call once exec -e PATH=/usr/bin:/bin -e MODE=b -- /usr/bin/printenv MODE
    The status should be success
    The stdout should match pattern 'b*'
    The stderr should include 'cache miss'
  End

  It 'starts subprocesses with a cleared environment'
    export ONCE_PROBE=leaked
    When call once exec -e PATH=/usr/bin:/bin -- /bin/sh -c '[ -z "${ONCE_PROBE:-}" ]'
    The status should be success
    The stderr should include 'exit=0'
  End

  It 'creates the CAS directory under the XDG cache home'
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'true' >/dev/null 2>&1
    When call test -d "$XDG_CACHE_HOME/once/cas"
    The status should be success
  End

  It 'reports the cache hit in well under 100ms'
    # Warm the cache with a deliberately slow command.
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'sleep 0.3' >/dev/null 2>&1
    start_ns=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    once exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'sleep 0.3' >/dev/null 2>&1
    end_ns=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
    When call test "$elapsed_ms" -lt 100
    The status should be success
  End

  Describe 'cwd'
    It 'resolves a workspace-relative cwd against the workspace root'
      # Use `pwd` (POSIX shell builtin) so the assertion checks the
      # cwd resolution itself, without depending on file-write timing
      # or external utilities discoverable through PATH.
      mkdir -p "$WORKSPACE/sub"
      When call once exec --cwd sub -e PATH=/usr/bin:/bin -- /bin/sh -c 'pwd'
      The status should be success
      The stdout should match pattern '*/sub*'
      The stderr should include 'cache miss'
    End

    It 'rejects an absolute cwd'
      When call once exec --cwd /tmp -e PATH=/usr/bin:/bin -- /bin/sh -c 'true'
      The status should not equal 0
      The stderr should include 'workspace path must be relative'
    End

    It 'rejects a parent-directory escape'
      When call once exec --cwd ../escape -e PATH=/usr/bin:/bin -- /bin/sh -c 'true'
      The status should not equal 0
      The stderr should include 'must not escape'
    End
  End

  Describe '--timeout-ms'
    It 'kills the child if the deadline elapses'
      When call once exec --timeout-ms 100 -e PATH=/usr/bin:/bin -- /bin/sh -c 'sleep 5'
      The status should not equal 0
      The stderr should include 'timeout'
    End
  End

  Describe '--format json'
    It 'emits a JSON trailer on stderr; stdout stays the wrapped program transparent'
      When call "$ONCE_BIN" --format json -C "$WORKSPACE" exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hello'
      The status should be success
      # Stdout is the program's literal output, untouched.
      The stdout should equal 'hello'
      # The Once trailer on stderr is now a JSON object.
      The stderr should include '"cache":"miss"'
      The stderr should include '"exit_code":0'
      The stderr should include '"action_digest":'
    End
  End

  Describe '--quiet'
    It 'suppresses the human trailer on stderr but keeps subprocess stdout'
      When call "$ONCE_BIN" --quiet -C "$WORKSPACE" exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hello'
      The status should be success
      # Wrapped program stdout still passes through untouched.
      The stdout should equal 'hello'
      # The "once: cache ..." trailer must not appear under --quiet.
      The stderr should not include 'cache miss'
      The stderr should not include 'once:'
    End

    It 'still emits the structured trailer when --quiet is combined with --format json'
      # --quiet only gates human trailers; machine consumers asked
      # for json get json regardless. Stdout remains the wrapped
      # program's bytes so existing pipelines stay parseable.
      When call "$ONCE_BIN" --quiet --format json -C "$WORKSPACE" exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hello'
      The status should be success
      The stdout should equal 'hello'
      The stderr should include '"cache":"miss"'
      The stderr should include '"exit_code":0'
    End

    It 'still surfaces errors when --quiet is set'
      # Errors travel to stderr through a different code path than the
      # success trailer; --quiet must not swallow them.
      When call "$ONCE_BIN" --quiet -C /nonexistent exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'true'
      The status should not equal 0
      The stderr should include 'once:'
    End

    It 'accepts the short -q alias'
      When call "$ONCE_BIN" -q -C "$WORKSPACE" exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hi'
      The status should be success
      The stdout should equal 'hi'
      The stderr should not include 'cache miss'
    End
  End

  Describe '--format toon'
    It 'emits a TOON trailer on stderr; stdout stays the wrapped program transparent'
      When call "$ONCE_BIN" --format toon -C "$WORKSPACE" exec -e PATH=/usr/bin:/bin -- /bin/sh -c 'printf hello'
      The status should be success
      The stdout should equal 'hello'
      The stderr should include 'cache: miss'
      The stderr should include 'exit_code: 0'
      The stderr should include 'action_digest:'
    End
  End

  Describe 'large outputs'
    big_exec() {
      "$ONCE_BIN" -C "$WORKSPACE" exec --timeout-ms 10000 \
        -e PATH=/usr/bin:/bin -- /bin/sh -c 'yes hello | head -c 4194304' \
        > "$WORKSPACE/big.out" 2>/dev/null
      wc -c "$WORKSPACE/big.out" | awk '{print $1}'
    }

    It 'streams multi-megabyte output without buffering everything'
      # Run via a helper so the 4 MB stream stays in a real file and
      # shellspec only sees the byte count on stdout.
      When call big_exec
      The status should be success
      The output should equal '4194304'
    End
  End
End
