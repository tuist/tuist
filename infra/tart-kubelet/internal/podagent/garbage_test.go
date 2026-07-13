package podagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

func TestIsNoSpaceError(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"nil", nil, false},
		{"unrelated", errors.New("connection refused"), false},
		// Foundation uses a curly apostrophe; the Sqlite layer Tart's
		// pull pipeline goes through speaks straight ENOSPC.
		{
			"curly-apostrophe",
			errors.New("Error: The file couldn’t be saved because there isn’t enough space."),
			true,
		},
		{
			"straight-apostrophe",
			errors.New("Error: The file couldn't be saved because there isn't enough space."),
			true,
		},
		{
			"sqlite",
			errors.New("ERROR: NSURLStorageURLCacheDB: database or disk is full"),
			true,
		},
		{
			"posix-enospc",
			errors.New("write /tmp/x: No space left on device"),
			true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsNoSpaceError(tc.err); got != tc.want {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
		})
	}
}

// A golden base with no backing Pod and past its retention window is a
// reap candidate — but only if it isn't currently running. On the staging
// host-Kura mini a golden was booted directly (launchd, serving
// benchmarks); with no liveness guard the GC killed it mid-session. These
// cases pin that the reap consults IsRunning before deleting.
func TestRunOnceSparesRunningVMs(t *testing.T) {
	const golden = goldenBaseVMPrefix + "deadbeef"
	const node = "mini-1"
	const retention = time.Hour
	now := time.Date(2026, 7, 9, 12, 0, 0, 0, time.UTC)

	newCollector := func(t *testing.T, isRunning func(context.Context, string) (bool, error)) (*Collector, string) {
		t.Helper()
		dir := t.TempDir()
		deletes := filepath.Join(dir, "deletes.txt")
		bin := filepath.Join(dir, "faketart")
		// `list` reports one stopped local golden; `delete` records the
		// name so the test can assert whether the reap fired.
		body := fmt.Sprintf("#!/bin/sh\n"+
			"if [ \"$1\" = \"list\" ]; then\n"+
			"  printf '%%s' '[{\"Name\":\"%s\",\"Source\":\"local\",\"State\":\"stopped\",\"CPU\":4,\"Memory\":8192,\"Size\":72}]'\n"+
			"elif [ \"$1\" = \"delete\" ]; then\n"+
			"  printf '%%s\\n' \"$2\" >> %q\n"+
			"fi\n", golden, deletes)
		if err := os.WriteFile(bin, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}

		scheme := runtime.NewScheme()
		if err := corev1.AddToScheme(scheme); err != nil {
			t.Fatalf("add core scheme: %v", err)
		}
		// No Pods scheduled here, so the golden is unreferenced.
		k := fake.NewClientBuilder().WithScheme(scheme).
			WithIndex(&corev1.Pod{}, "spec.nodeName", func(o client.Object) []string {
				return []string{o.(*corev1.Pod).Spec.NodeName}
			}).Build()

		c := &Collector{
			K8s:             k,
			Tart:            &tart.Client{Binary: bin},
			NodeName:        node,
			GoldenRetention: retention,
			Now:             func() time.Time { return now },
			IsRunning:       isRunning,
			// Last seen unreferenced 2h ago (retention 1h): absent the
			// liveness guard, this golden reaps.
			goldenSeen: map[string]time.Time{golden: now.Add(-2 * retention)},
		}
		return c, deletes
	}

	deleted := func(t *testing.T, deletes string) bool {
		t.Helper()
		b, err := os.ReadFile(deletes)
		if errors.Is(err, os.ErrNotExist) {
			return false
		}
		if err != nil {
			t.Fatal(err)
		}
		return strings.Contains(string(b), golden)
	}

	t.Run("running golden past retention is spared", func(t *testing.T) {
		c, deletes := newCollector(t, func(context.Context, string) (bool, error) { return true, nil })
		c.RunOnce(context.Background())
		if deleted(t, deletes) {
			t.Fatal("running golden past retention was deleted")
		}
	})

	t.Run("stopped golden past retention is reaped", func(t *testing.T) {
		c, deletes := newCollector(t, func(context.Context, string) (bool, error) { return false, nil })
		c.RunOnce(context.Background())
		if !deleted(t, deletes) {
			t.Fatal("stopped golden past retention was not reaped")
		}
	})

	t.Run("unreadable liveness signal spares the VM (fail-safe)", func(t *testing.T) {
		c, deletes := newCollector(t, func(context.Context, string) (bool, error) {
			return false, errors.New("pgrep boom")
		})
		c.RunOnce(context.Background())
		if deleted(t, deletes) {
			t.Fatal("golden was reaped despite an unreadable liveness signal")
		}
	})
}
