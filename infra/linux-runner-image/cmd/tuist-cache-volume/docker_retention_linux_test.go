//go:build linux

package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestDockerRetentionBoundsAllBuilderKeysAndImages(t *testing.T) {
	for _, host := range []string{"", dockerMergeHost} {
		t.Run(host, func(t *testing.T) {
			root := t.TempDir()
			old, recent := "buildx_buildkit_tuist-"+strings.Repeat("a", 32)+"0_state", "buildx_buildkit_tuist-"+strings.Repeat("b", 32)+"0_state"
			image, now := dockerID("c"), time.Now()
			builders := dockerLedger{old: {LastUsedAt: now.Add(-48 * time.Hour)}, recent: {LastUsedAt: now}}
			if err := writeDockerLedger(dockerBuilderLedger(root), builders); err != nil {
				t.Fatal(err)
			}
			ledger := dockerLedger{image: {LastUsedAt: now.Add(-24 * time.Hour)}}
			used := int64(34)
			var removed []string
			d := &daemon{usedBytes: func(got string) (int64, error) {
				if got != root {
					t.Fatal(got)
				}
				return used, nil
			}}
			d.run = func(_ context.Context, name string, args ...string) ([]byte, error) {
				if host != "" {
					if !reflect.DeepEqual(args[:2], []string{"--host", host}) {
						t.Fatalf("wrong daemon: %v", args)
					}
					args = args[2:]
				}
				switch strings.Join(args[:2], " ") {
				case "image ls":
					return []byte(image), nil
				case "image inspect":
					return json.Marshal([]dockerImage{{ID: image}})
				case "volume ls":
					return []byte(old + "\n" + recent), nil
				case "volume inspect":
					var volumes []buildkitVolume
					for _, n := range []string{old, recent} {
						volumes = append(volumes, buildkitVolume{Name: n, Driver: "local", Mountpoint: filepath.Join(root, "volumes", n, "_data"), Labels: map[string]string{"dev.tuist.cache": "buildkit"}})
					}
					return json.Marshal(volumes)
				case "volume rm", "image rm":
					removed = append(removed, args[3])
					used -= 5
					return nil, nil
				}
				t.Fatalf("unexpected %s %v", name, args)
				return nil, nil
			}
			if err := d.retainDocker(context.Background(), host, root, ledger, 26); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(removed, []string{old, image}) {
				t.Fatalf("evictions: %v", removed)
			}
			if got := readDockerLedger(dockerBuilderLedger(root)); len(got) != 1 || got[recent].LastUsedAt.IsZero() {
				t.Fatal(got)
			}
			if len(readDockerLedger(dockerLedgerFile(root))) != 0 {
				t.Fatal("evicted image still in inventory")
			}
		})
	}
}

func TestDockerRetentionFailsClosedOnUsageErrors(t *testing.T) {
	d := &daemon{usedBytes: func(string) (int64, error) { return 0, errors.New("statfs failed") }, run: func(context.Context, string, ...string) ([]byte, error) {
		t.Fatal("removed data without knowing usage")
		return nil, nil
	}}
	if err := d.retainDocker(context.Background(), "", t.TempDir(), nil, 26); err == nil {
		t.Fatal("ignored usage failure")
	}
}

func TestDockerTrimFailureWithholdsTeardown(t *testing.T) {
	d, source, calls := fakeDaemon(t, true)
	if _, err := d.handle(dockerMessage{Docker: "switch", Source: source}); err != nil {
		t.Fatal(err)
	}
	run := d.run
	d.run = func(ctx context.Context, name string, args ...string) ([]byte, error) {
		if name == "fstrim" {
			return nil, errors.New("discard unsupported")
		}
		return run(ctx, name, args...)
	}
	if _, err := d.handle(dockerMessage{Docker: "teardown"}); err == nil {
		t.Fatal("trim failure ignored")
	}
	if readTeardownReport(t, d).Clean {
		t.Fatal("untrimmed snapshot eligible for publication")
	}
	if !strings.Contains(strings.Join(*calls, "\n"), "umount "+d.dataRoot) {
		t.Fatal("trim failure skipped unmount")
	}
}

// Real discard proof runs only in the disposable privileged CI container.
func TestDockerTrimReclaimsDeletedBlocks(t *testing.T) {
	if os.Getenv("TUIST_TEST_DOCKER_CACHE") != "1" {
		t.Skip("requires isolated privileged container")
	}
	root := t.TempDir()
	image, mount := filepath.Join(root, "disk.img"), filepath.Join(root, "mount")
	if err := os.Mkdir(mount, 0700); err != nil {
		t.Fatal(err)
	}
	f, err := os.Create(image)
	if err != nil {
		t.Fatal(err)
	}
	if err = f.Truncate(256 << 20); err != nil {
		t.Fatal(err)
	}
	f.Close()
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	run := func(ctx context.Context, name string, args ...string) ([]byte, error) {
		return exec.CommandContext(ctx, name, args...).CombinedOutput()
	}
	command := func(name string, args ...string) {
		t.Helper()
		if out, err := run(ctx, name, args...); err != nil {
			t.Fatalf("%s: %v: %s", name, err, out)
		}
	}
	command("mkfs.ext4", append(dockerFormatArgs, image)...)
	command("mount", "-o", "loop", image, mount)
	defer run(context.Background(), "umount", mount)
	command("dd", "if=/dev/urandom", "of="+filepath.Join(mount, "deleted"), "bs=1M", "count=64", "conv=fsync")
	allocated := func() int64 {
		t.Helper()
		info, err := os.Stat(image)
		if err != nil {
			t.Fatal(err)
		}
		return info.Sys().(*syscall.Stat_t).Blocks * 512
	}
	before := allocated()
	if err := os.Remove(filepath.Join(mount, "deleted")); err != nil {
		t.Fatal(err)
	}
	d := &daemon{run: run}
	if err := d.trimDocker(ctx, mount); err != nil {
		t.Fatal(err)
	}
	if after := allocated(); before-after < 60<<20 {
		t.Fatalf("discard did not reclaim payload: before=%d after=%d", before, after)
	}
}
