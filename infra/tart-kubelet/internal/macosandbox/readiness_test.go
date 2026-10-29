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
run) while [ ! -f "$TART_HOME/exit" ]; do sleep 0.05; done ;;
exec)
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
			ctx, cancel := context.WithTimeout(t.Context(), time.Second)
			defer cancel()
			runtime := &TartRuntime{Client: c}
			record := &Record{}
			record.SandboxID = "readiness"
			err = runtime.waitGuestReady(ctx, record, h)
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
			}
		})
	}
}
