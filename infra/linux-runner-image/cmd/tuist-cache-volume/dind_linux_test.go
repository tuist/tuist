//go:build linux

package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeDaemon runs `sleep` as dockerd and answers every other command from
// mounts, which reports whether each `mount` succeeds, in order.
func fakeDaemon(t *testing.T, mounts ...bool) (*daemon, string, *[]string) {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, dockerTestScope), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, dockerTestScope, dockerImageName), nil, 0600); err != nil {
		t.Fatal(err)
	}
	var calls []string
	d := &daemon{args: []string{"sleep", "60"}, root: root, ephemeral: "/ephemeral.img", state: "ephemeral"}
	d.run = func(_ context.Context, name string, args ...string) ([]byte, error) {
		calls = append(calls, strings.Join(append([]string{name}, args...), " "))
		if name == "mount" && len(args) == 4 && args[3] == dockerDataRoot && strings.HasSuffix(args[2], dockerImageName) {
			ok := mounts[0]
			mounts = mounts[1:]
			if !ok {
				return []byte("mounting /dev/loop0 on /var/lib/docker failed: Invalid argument"), errors.New("exit status 255")
			}
		}
		return nil, nil
	}
	t.Cleanup(func() { d.mu.Lock(); d.stop(); d.mu.Unlock() })
	return d, dockerTestScope + "/" + dockerImageName, &calls
}

func TestSwitchFormatsADataRootTheKernelRefuses(t *testing.T) {
	d, source, calls := fakeDaemon(t, false, true)
	reply, err := d.handle(dockerMessage{Docker: "switch", Source: source})
	if err != nil || reply != dockerReset {
		t.Fatalf("switch: %q, %v", reply, err)
	}
	if !d.reset || d.state != "volume" {
		t.Fatalf("reset %t, state %s", d.reset, d.state)
	}
	formatted := false
	for _, call := range *calls {
		if strings.HasPrefix(call, "mkfs.ext4 "+strings.Join(dockerFormatArgs, " ")) && strings.HasSuffix(call, source) {
			formatted = true
		}
	}
	if !formatted {
		t.Fatalf("the refused data root was not formatted: %v", *calls)
	}
}

func TestSwitchFallsBackWhenTheFormattedRootStillFailsToMount(t *testing.T) {
	d, source, calls := fakeDaemon(t, false, false)
	if _, err := d.handle(dockerMessage{Docker: "switch", Source: source}); err == nil {
		t.Fatal("switched onto a data root that failed to mount")
	}
	if d.state != "ephemeral" {
		t.Fatalf("state %s", d.state)
	}
	if !strings.Contains(strings.Join(*calls, "\n"), "mount -o loop /ephemeral.img "+dockerDataRoot) {
		t.Fatalf("did not return to the ephemeral data root: %v", *calls)
	}
}

func TestSwitchKeepsASavedDataRootThatMounts(t *testing.T) {
	d, source, calls := fakeDaemon(t, true)
	reply, err := d.handle(dockerMessage{Docker: "switch", Source: source})
	if err != nil || reply != "ok" || d.reset {
		t.Fatalf("switch: %q, %v, reset %t", reply, err, d.reset)
	}
	for _, call := range *calls {
		if strings.HasPrefix(call, "mkfs") {
			t.Fatalf("formatted a data root that mounted: %v", *calls)
		}
	}
}
