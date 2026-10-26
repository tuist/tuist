//go:build linux

package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
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
	d := &daemon{args: []string{"sleep", "60"}, root: root, ephemeral: "/ephemeral.img", state: "ephemeral", dataRoot: t.TempDir(), mergeRoot: filepath.Join(t.TempDir(), "merge")}
	d.run = func(_ context.Context, name string, args ...string) ([]byte, error) {
		calls = append(calls, strings.Join(append([]string{name}, args...), " "))
		if name == "mount" && len(args) == 4 && args[3] == d.dataRoot && strings.HasSuffix(args[2], dockerImageName) {
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
	if !strings.Contains(strings.Join(*calls, "\n"), "mount -o loop /ephemeral.img "+d.dataRoot) {
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

// mergingDaemon is a supervisor whose job's data root keeps branch and whose
// saved head's clone keeps head, with the job switched onto its data root and
// the head's clone beside it.
func mergingDaemon(t *testing.T, branch, head []dockerImage, pipeErr error) (*daemon, *[][]string) {
	t.Helper()
	d, source, _ := fakeDaemon(t, true)
	if _, err := d.handle(dockerMessage{Docker: "switch", Source: source}); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(d.root, dockerTestScope, dockerMergeImageName), nil, 0600); err != nil {
		t.Fatal(err)
	}
	inspect := func(images []dockerImage) []byte {
		data, _ := json.Marshal(images)
		return data
	}
	ids := func(images []dockerImage) []byte {
		var lines []string
		for _, image := range images {
			lines = append(lines, image.ID)
		}
		return []byte(strings.Join(lines, "\n"))
	}
	d.run = func(_ context.Context, name string, args ...string) ([]byte, error) {
		images := branch
		if len(args) > 1 && args[0] == "--host" {
			images, args = head, args[2:]
		}
		if name != "docker" || len(args) < 2 {
			return nil, nil
		}
		switch strings.Join(args[:2], " ") {
		case "image ls":
			return ids(images), nil
		case "image inspect":
			return inspect(images), nil
		}
		return nil, nil
	}
	var piped [][]string
	d.pipe = func(_ context.Context, from, to []string) error {
		piped = append(piped, from, to)
		return pipeErr
	}
	return d, &piped
}

func internalImage(id string, size int64) dockerImage {
	return dockerImage{ID: id, RepoTags: []string{dockerInternalReference(id)}, Size: size}
}

func readTeardownReport(t *testing.T, d *daemon) dockerTeardownReport {
	t.Helper()
	var report dockerTeardownReport
	data, err := os.ReadFile(filepath.Join(d.root, dockerTestScope, dockerReport))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &report); err != nil {
		t.Fatal(err)
	}
	return report
}

func TestTeardownMergesTheJobsNewImageIntoTheSavedHead(t *testing.T) {
	alpine, postgres, flutter := internalImage(dockerID("a"), 8_000_000), internalImage(dockerID("b"), 450_000_000), internalImage(dockerID("c"), 6_000_000_000)
	d, piped := mergingDaemon(t, []dockerImage{alpine, postgres}, []dockerImage{postgres, flutter}, nil)
	if _, err := d.handle(dockerMessage{Docker: "teardown", Merge: dockerTestScope + "/" + dockerMergeImageName, Generation: 4}); err != nil {
		t.Fatal(err)
	}
	want := [][]string{{"save", dockerInternalReference(alpine.ID)}, {"--host", dockerMergeHost, "load", "-q"}}
	if !reflect.DeepEqual(*piped, want) {
		t.Fatalf("piped %v", *piped)
	}
	report := readTeardownReport(t, d)
	if report.MergedGeneration != 4 || report.MergedInto != "head" || !report.Clean || !report.Changed {
		t.Fatalf("report %+v", report)
	}
	if _, err := os.Stat(dockerLedgerFile(d.mergeRoot)); err != nil {
		t.Fatalf("the saved head's ledger was not merged: %v", err)
	}
}

func TestTeardownWithoutAMergeLeavesTheDataRootAsTheJobLeftIt(t *testing.T) {
	alpine, postgres, flutter := internalImage(dockerID("a"), 8_000_000), internalImage(dockerID("b"), 450_000_000), internalImage(dockerID("c"), 6_000_000_000)
	for name, test := range map[string]struct {
		branch, head []dockerImage
		pipeErr      error
	}{
		"the copy failed":        {branch: []dockerImage{alpine, postgres}, head: []dockerImage{postgres, flutter}, pipeErr: errors.New("load failed")},
		"nothing the head lacks": {branch: []dockerImage{postgres}, head: []dockerImage{alpine, postgres}},
	} {
		t.Run(name, func(t *testing.T) {
			d, _ := mergingDaemon(t, test.branch, test.head, test.pipeErr)
			if _, err := d.handle(dockerMessage{Docker: "teardown", Merge: dockerTestScope + "/" + dockerMergeImageName, Generation: 4}); err != nil {
				t.Fatal(err)
			}
			if report := readTeardownReport(t, d); report.MergedGeneration != 0 || report.MergedInto != "" || !report.Clean {
				t.Fatalf("report %+v", report)
			}
		})
	}
}

func TestTeardownRebasesADataRootThatAlreadyHoldsTheSavedHead(t *testing.T) {
	alpine, postgres := internalImage(dockerID("a"), 8_000_000), internalImage(dockerID("b"), 450_000_000)
	d, piped := mergingDaemon(t, []dockerImage{alpine, postgres}, []dockerImage{postgres}, nil)
	if _, err := d.handle(dockerMessage{Docker: "teardown", Merge: dockerTestScope + "/" + dockerMergeImageName, Generation: 4}); err != nil {
		t.Fatal(err)
	}
	if len(*piped) != 0 {
		t.Fatalf("copied %v", *piped)
	}
	if report := readTeardownReport(t, d); report.MergedGeneration != 4 || report.MergedInto != "branch" {
		t.Fatalf("report %+v", report)
	}
}
