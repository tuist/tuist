//go:build linux

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func TestMergeBuildkitVolumesKeepsUnrelatedKeysAndSelectsCompleteStates(t *testing.T) {
	for _, into := range []string{"branch", "head"} {
		for _, changed := range []bool{false, true} {
			t.Run(fmt.Sprintf("into=%s/changed=%t", into, changed), func(t *testing.T) {
				d := &daemon{dataRoot: t.TempDir(), mergeRoot: t.TempDir(), base: dockerSnapshot{BuildVolumes: map[string]string{}}}
				key := func(s string) string { return "buildx_buildkit_tuist-" + digest(s)[:32] + "0_state" }
				shared, branchOnly, headOnly := key("shared"), key("branch"), key("head")
				states := map[string]map[string]string{d.dataRoot: {shared: "branch", branchOnly: "branch-only"}, d.mergeRoot: {shared: "head", headOnly: "head-only"}}
				for root, entries := range states {
					for name, value := range entries {
						path := filepath.Join(root, "volumes", name, "_data")
						if err := os.MkdirAll(path, 0700); err != nil {
							t.Fatal(err)
						}
						if err := os.WriteFile(filepath.Join(path, "state"), []byte(value), 0600); err != nil {
							t.Fatal(err)
						}
						if err := unix.Setxattr(filepath.Join(path, "state"), "user.tuist-test", []byte(value), 0); err != nil {
							t.Fatal(err)
						}
						if err := os.Link(filepath.Join(path, "state"), filepath.Join(path, "hardlink")); err != nil {
							t.Fatal(err)
						}
					}
				}
				d.base.BuildVolumes[shared] = "branch"
				if changed {
					d.base.BuildVolumes[shared] = "previous"
				}
				d.run = func(ctx context.Context, name string, args ...string) ([]byte, error) {
					if name == "cp" {
						return exec.CommandContext(ctx, name, args...).CombinedOutput()
					}
					root := d.dataRoot
					if args[0] == "--host" {
						root, args = d.mergeRoot, args[2:]
					}
					switch args[1] {
					case "ls":
						var names []string
						for name := range states[root] {
							names = append(names, name)
						}
						return []byte(strings.Join(names, "\n")), nil
					case "inspect":
						var volumes []buildkitVolume
						for _, name := range args[2:] {
							volumes = append(volumes, buildkitVolume{Name: name, Driver: "local", Mountpoint: filepath.Join(root, "volumes", name, "_data"), Labels: map[string]string{"dev.tuist.cache": "buildkit"}})
						}
						return json.Marshal(volumes)
					case "create":
						name := args[len(args)-1]
						states[root][name] = "created"
						return nil, os.MkdirAll(filepath.Join(root, "volumes", name, "_data"), 0700)
					}
					return nil, fmt.Errorf("unexpected command %v", args)
				}
				branch := dockerSnapshot{BuildVolumes: map[string]string{shared: "branch", branchOnly: "branch-only"}}
				head := dockerSnapshot{BuildVolumes: map[string]string{shared: "head", headOnly: "head-only"}}
				if err := d.mergeBuildkitVolumes(context.Background(), into, branch, head); err != nil {
					t.Fatal(err)
				}
				root := d.dataRoot
				if into == "head" {
					root = d.mergeRoot
				}
				winner := "head"
				if changed {
					winner = "branch"
				}
				for name, want := range map[string]string{shared: winner, branchOnly: "branch-only", headOnly: "head-only"} {
					got, err := os.ReadFile(filepath.Join(root, "volumes", name, "_data", "state"))
					if err != nil || string(got) != want {
						t.Fatalf("%s: got %q, want %q, %v", name, got, want, err)
					}
					path := filepath.Join(root, "volumes", name, "_data")
					attribute := make([]byte, 128)
					n, err := unix.Getxattr(filepath.Join(path, "state"), "user.tuist-test", attribute)
					if err != nil || string(attribute[:n]) != want {
						t.Fatalf("lost xattr: %v", err)
					}
					state, err := os.Stat(filepath.Join(path, "state"))
					if err != nil {
						t.Fatal(err)
					}
					link, err := os.Stat(filepath.Join(path, "hardlink"))
					if err != nil || !os.SameFile(state, link) {
						t.Fatalf("lost hard link: %v", err)
					}
				}
			})
		}
	}
}

func TestBuildCacheFingerprintKeepsSmallLayersAndCacheMountWrites(t *testing.T) {
	base := []buildCacheRecord{{ID: "layer", CacheType: "regular", Size: "32B", LastUsedAt: "before"}}
	same := []buildCacheRecord{{ID: "layer", CacheType: "regular", Size: "32B", LastUsedAt: "after"}, {ID: "context", CacheType: "source.local", Size: "4kB"}}
	if buildCacheFingerprint(base) != buildCacheFingerprint(same) {
		t.Fatal("reading an existing layer or sending a context republished the cache")
	}
	if buildCacheFingerprint(base) == buildCacheFingerprint(append(same, buildCacheRecord{ID: "new", CacheType: "regular", Size: "1B"})) {
		t.Fatal("lost a layer smaller than 1 GB")
	}
	before := []buildCacheRecord{{ID: "mount", CacheType: "exec.cachemount", Size: "32B", LastUsedAt: "before"}}
	after := []buildCacheRecord{{ID: "mount", CacheType: "exec.cachemount", Size: "32B", LastUsedAt: "after"}}
	if buildCacheFingerprint(before) == buildCacheFingerprint(after) {
		t.Fatal("lost an in-place cache mount write")
	}
}

func TestMergeBuildkitVolumesRefusesAnExistingUnlabelledDestination(t *testing.T) {
	d := &daemon{dataRoot: t.TempDir(), mergeRoot: t.TempDir(), base: dockerSnapshot{}}
	name := "buildx_buildkit_tuist-" + digest("target")[:32] + "0_state"
	d.run = func(_ context.Context, command string, args ...string) ([]byte, error) {
		if command != "docker" {
			t.Fatal("touched a volume before validating its explicit destination")
		}
		root, labels := d.dataRoot, map[string]string{"dev.tuist.cache": "buildkit"}
		if args[0] == "--host" {
			root, labels, args = d.mergeRoot, nil, args[2:]
		}
		if args[1] == "create" {
			return nil, nil
		}
		return json.Marshal([]buildkitVolume{{Name: name, Driver: "local", Mountpoint: filepath.Join(root, "volumes", name, "_data"), Labels: labels}})
	}
	if err := d.mergeBuildkitVolumes(context.Background(), "head", dockerSnapshot{BuildVolumes: map[string]string{name: "new"}}, dockerSnapshot{}); err == nil {
		t.Fatal("accepted an unlabelled same-name target")
	}
}

func TestBuildkitVolumesRejectArbitraryAndExternalStorage(t *testing.T) {
	root := "/var/lib/docker"
	name := "buildx_buildkit_tuist-0123456789abcdef0123456789abcdef0_state"
	valid := buildkitVolume{Name: name, Driver: "local", Mountpoint: filepath.Join(root, "volumes", name, "_data"), Labels: map[string]string{"dev.tuist.cache": "buildkit"}}
	if !valid.valid(root) {
		t.Fatal("refused the action's BuildKit volume")
	}
	for _, mutate := range []func(*buildkitVolume){
		func(v *buildkitVolume) { v.Name = "postgres-data" },
		func(v *buildkitVolume) { v.Driver = "nfs" },
		func(v *buildkitVolume) { v.Options = map[string]string{"device": "/etc", "o": "bind"} },
		func(v *buildkitVolume) { v.Mountpoint = "/etc" },
		func(v *buildkitVolume) { v.Labels = nil },
	} {
		v := valid
		mutate(&v)
		if v.valid(root) {
			t.Fatalf("accepted unsafe volume %+v", v)
		}
	}
}

func TestBuildkitFingerprintDetectsSameSizeWritesWithoutFollowingSymlinks(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "cache")
	if err := os.WriteFile(path, []byte("before"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/not-readable", filepath.Join(root, "link")); err != nil {
		t.Fatal(err)
	}
	before, err := buildkitVolumeFingerprint(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	if same, err := buildkitVolumeFingerprint(context.Background(), root); err != nil || same != before {
		t.Fatalf("unchanged tree: %s, %v", same, err)
	}
	if err := os.WriteFile(path, []byte("after!"), 0600); err != nil {
		t.Fatal(err)
	}
	later := time.Now().Add(time.Second)
	if err := os.Chtimes(path, later, later); err != nil {
		t.Fatal(err)
	}
	if after, err := buildkitVolumeFingerprint(context.Background(), root); err != nil || after == before {
		t.Fatalf("missed same-sized cache write: %s, %v", after, err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := buildkitVolumeFingerprint(ctx, root); err == nil {
		t.Fatal("ignored cancellation")
	}
}

func TestTeardownKeepsBuildOnlyChangesWhenHeadHasTheSameImages(t *testing.T) {
	image := internalImage(dockerID("a"), 8_000_000)
	d, _ := mergingDaemon(t, []dockerImage{image}, []dockerImage{image}, nil)
	d.base.BuildCache = "old build state"
	if _, err := d.handle(dockerMessage{Docker: "teardown", Merge: dockerTestScope + "/" + dockerMergeImageName, Generation: 4}); err != nil {
		t.Fatal(err)
	}
	report := readTeardownReport(t, d)
	if !report.Changed || report.MergedInto != "branch" || report.MergedGeneration != 4 {
		t.Fatalf("lost build-only changes during rebase: %+v", report)
	}
}
