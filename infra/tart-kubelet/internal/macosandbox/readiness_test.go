package macosandbox

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

func TestGuestReadinessWaitsForBridge(t *testing.T) {
	for _, response := range []string{"transient-exec-failure", "wrong-reply", "unavailable"} {
		t.Run(response, func(t *testing.T) {
			dir := t.TempDir()
			binary := filepath.Join(dir, "tart")
			script := `#!/bin/sh
set -eu
case "$1" in
run)
  # Like the patched runtime: the control channel answers only once the
  # restore has returned.
  vm="$TART_HOME/vms/sbx-readiness"
  mkdir -p "$vm"
  sleep 0.3
  touch "$TART_HOME/restored"
  while [ ! -f "$TART_HOME/exit" ]; do
    if [ -f "$vm/sandbox-request.json" ]; then
      id=$(sed 's/.*"id":"\([^"]*\)".*/\1/' "$vm/sandbox-request.json")
      printf '{"id":"%s","action":"status","instance":"11111111-1111-1111-1111-111111111111","pid":1,"state":"running"}' "$id" > "$vm/sandbox-reply.json"
    fi
    sleep 0.02
  done ;;
exec)
  if [ ! -f "$TART_HOME/restored" ]; then touch "$TART_HOME/early-exec"; exit 1; fi
  # A built-in readiness probe succeeds even while the bridge is unavailable.
  if [ "$3" = /usr/bin/true ]; then exit 0; fi
  read -r request
  [ "$request" = '{"op":"ping"}' ]
  if [ ! -f "$TART_HOME/probed" ]; then
    touch "$TART_HOME/probed"
    case '` + response + `' in
      transient-exec-failure) exit 126 ;;
      wrong-reply) echo '{"type":"exit"}'; exit 0 ;;
    esac
  fi
  if [ '` + response + `' = unavailable ]; then exit 126; fi
  touch "$TART_HOME/ready"
  echo '{"type":"pong"}' ;;
esac
`
			if err := os.WriteFile(binary, []byte(script), 0700); err != nil {
				t.Fatal(err)
			}
			c := &tart.Client{Binary: binary, HomeDir: dir, LogDir: filepath.Join(dir, "logs")}
			h, err := c.StartWithOptions(t.Context(), "readiness", tart.RunOptions{})
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() {
				_ = os.WriteFile(filepath.Join(dir, "exit"), nil, 0600)
				select {
				case <-h.Done():
				case <-time.After(3 * time.Second):
					t.Error("fake runtime did not exit")
				}
			})
			ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
			defer cancel()
			runtime := &TartRuntime{Client: c}
			record := &Record{}
			record.SandboxID = "readiness"
			_, err = runtime.waitGuestReady(ctx, record, h)
			if response == "unavailable" {
				if !errors.Is(err, context.DeadlineExceeded) {
					t.Fatalf("unavailable bridge accepted: %v", err)
				}
				if _, exited := h.Exited(); exited {
					t.Fatal("readiness timeout stopped the reserved VM")
				}
			} else {
				if err != nil {
					t.Fatal(err)
				}
				if _, err := os.Stat(filepath.Join(dir, "ready")); err != nil {
					t.Fatal("readiness returned before the bridge answered pong")
				}
				if _, err := os.Stat(filepath.Join(dir, "early-exec")); err == nil {
					t.Fatal("a guest command ran before the runtime's restore returned")
				}
			}
		})
	}
}
