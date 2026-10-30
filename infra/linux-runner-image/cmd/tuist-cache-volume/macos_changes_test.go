package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

// mountedVolume acquires a volume through the mailbox with a no-op hdiutil, so
// its mount point is a plain directory the test can change.
func mountedVolume(t *testing.T, seed map[string]string) (share, mount, base string) {
	t.Helper()
	share, mount = t.TempDir(), t.TempDir()
	response := macResponse{Directory: digest("volume"), ID: "lease", Warm: true}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	makeShare(t, share, response.Directory)
	base = filepath.Join(mount, response.Directory)
	for name, contents := range seed {
		writeVolumeFile(t, base, name, contents)
	}
	if _, _, _, err := acquireMacAt(context.Background(), "key", 0, share, mount, func(string, string) error { return nil }); err != nil {
		t.Fatal(err)
	}
	// A job's writes come after the mount; make sure the test's do too. File
	// times come from the kernel's coarse clock, which lags time.Now, so wait
	// until a new file's ctime is past the mount's.
	var mounted unix.Stat_t
	if err := unix.Lstat(filepath.Join(base, ".tuist-volume"), &mounted); err != nil {
		t.Fatal(err)
	}
	probe := filepath.Join(t.TempDir(), "probe")
	for {
		if err := os.WriteFile(probe, nil, 0644); err != nil {
			t.Fatal(err)
		}
		var stat unix.Stat_t
		if err := unix.Lstat(probe, &stat); err != nil {
			t.Fatal(err)
		}
		if stat.Ctim.Nano() > mounted.Ctim.Nano() {
			return share, mount, base
		}
		time.Sleep(time.Millisecond)
	}
}

func writeVolumeFile(t *testing.T, base, name, contents string) {
	t.Helper()
	path := filepath.Join(base, name)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(contents), 0644); err != nil {
		t.Fatal(err)
	}
}

func reportedChange(t *testing.T, share, mount string) bool {
	t.Helper()
	if err := detachMacAt(share, mount, func(...string) error { return nil }, fakeMacMeasure, func(string, bool) {}, func() {}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(share, digest("volume"), ".usage"))
	if err != nil {
		t.Fatal(err)
	}
	var usage struct {
		Changed *bool `json:"changed"`
	}
	if err = json.Unmarshal(data, &usage); err != nil {
		t.Fatal(err)
	}
	if usage.Changed == nil {
		t.Fatal("usage does not say whether the volume changed:", string(data))
	}
	return *usage.Changed
}

func TestMacReportsAnUntouchedVolumeAsUnchanged(t *testing.T) {
	share, mount, base := mountedVolume(t, map[string]string{"data/dependency.jar": "saved"})
	// macOS creates its own bookkeeping at the root of a mounted volume.
	writeVolumeFile(t, base, ".fseventsd/0000", "events")

	if reportedChange(t, share, mount) {
		t.Fatal("an untouched volume was reported as changed")
	}
}

func TestMacReportsChangesToTheVolume(t *testing.T) {
	for name, change := range map[string]func(t *testing.T, base string){
		"added file":      func(t *testing.T, base string) { writeVolumeFile(t, base, "data/new.jar", "new") },
		"resized file":    func(t *testing.T, base string) { writeVolumeFile(t, base, "data/dependency.jar", "saved and grown") },
		"removed file":    func(t *testing.T, base string) { _ = os.Remove(filepath.Join(base, "data", "dependency.jar")) },
		"added directory": func(t *testing.T, base string) { writeVolumeFile(t, base, digest("second")+"/file", "new") },
		"restored with old times": func(t *testing.T, base string) {
			writeVolumeFile(t, base, "data/restored.jar", "restored")
			earlier := time.Now().Add(-24 * time.Hour)
			_ = os.Chtimes(filepath.Join(base, "data", "restored.jar"), earlier, earlier)
		},
		"rewritten file": func(t *testing.T, base string) {
			path := filepath.Join(base, "data", "dependency.jar")
			writeVolumeFile(t, base, "data/dependency.jar", "SAVED")
			later := time.Now().Add(time.Hour)
			_ = os.Chtimes(path, later, later)
		},
	} {
		t.Run(name, func(t *testing.T) {
			share, mount, base := mountedVolume(t, map[string]string{"data/dependency.jar": "saved"})
			change(t, base)

			if !reportedChange(t, share, mount) {
				t.Fatal("a changed volume was reported as unchanged")
			}
		})
	}
}

func TestMacReportsAVolumeWithoutABaselineAsChanged(t *testing.T) {
	share, mount, _ := mountedVolume(t, map[string]string{"data/dependency.jar": "saved"})
	if err := os.Remove(baselinePath(mount, digest("volume"))); err != nil {
		t.Fatal(err)
	}

	if !reportedChange(t, share, mount) {
		t.Fatal("a volume without a recorded baseline was reported as unchanged")
	}
}

func TestMacDetachRemovesTheBaseline(t *testing.T) {
	share, mount, _ := mountedVolume(t, nil)
	reportedChange(t, share, mount)

	if _, err := os.Stat(baselinePath(mount, digest("volume"))); !os.IsNotExist(err) {
		t.Fatal("left the baseline behind:", err)
	}
}

func TestMacReportsAnUnchangedPathManifestAsUnchanged(t *testing.T) {
	share, mount, base := mountedVolume(t, map[string]string{
		"data/dependency.jar": "saved",
		manifestName:          `{"version":1,"paths":{".gradle":"data"}}` + "\n",
	})
	if got := attachLayout(t, base, ".gradle"); got[".gradle"] != "data" {
		t.Fatal(got)
	}

	if reportedChange(t, share, mount) {
		t.Fatal("attaching the recorded layout was reported as a change")
	}
}

func TestMacReportsANewPathManifestAsChanged(t *testing.T) {
	share, mount, base := mountedVolume(t, map[string]string{"data/dependency.jar": "saved"})
	if got := attachLayout(t, base, ".gradle"); got[".gradle"] != "data" {
		t.Fatal(got)
	}

	if !reportedChange(t, share, mount) {
		t.Fatal("recording the path layout was not reported as a change")
	}
}
