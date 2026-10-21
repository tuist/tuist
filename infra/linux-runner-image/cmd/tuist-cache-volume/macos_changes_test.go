package main

import (
	"context"
	"encoding/json"
	"errors"
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
	return mountedVolumeWithKey(t, "key", seed)
}

func mountedVolumeWithKey(t *testing.T, key string, seed map[string]string) (share, mount, base string) {
	t.Helper()
	share, mount = t.TempDir(), t.TempDir()
	response := macResponse{Directory: digest("volume"), ID: "lease", Warm: true}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	_ = os.Mkdir(filepath.Join(share, response.Directory), 0755)
	base = filepath.Join(mount, response.Directory)
	for name, contents := range seed {
		writeVolumeFile(t, base, name, contents)
	}
	if _, _, _, err := acquireMacAt(context.Background(), key, share, mount, func(...string) error { return nil }); err != nil {
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

// managedSeed is a warm module cache and compilation cache as the runner
// stages them: content-addressed entries the CLI and the compilers reuse.
var managedSeed = map[string]string{
	"data/tuist/Binaries/1f2e/Core.xcframework/Info.plist": "plist",
	"data/tuist/Manifests/1.0a9f":                          "manifest",
	"data/tuist/GenerationMetadata/cfbc.json":              `{"generationId":"aaaa"}`,
	"data/tuist/.support-cache-sweep":                      "",
	"data/plugin/v1.1/index.v1":                            "index",
	"data/plugin/v1.1/data.v1":                             "data",
	"data/plugin/lock":                                     "",
}

func TestMacReportsAManagedVolumeThatWasOnlyReadAsUnchanged(t *testing.T) {
	for _, key := range []string{"tuist-module", "tuist-xcode"} {
		for name, use := range map[string]func(t *testing.T, base string){
			// The CLI refreshes the modification time of every cache entry it hits.
			"cache hits": func(t *testing.T, base string) {
				now := time.Now()
				for _, entry := range []string{"data/tuist/Binaries/1f2e", "data/tuist/Manifests/1.0a9f"} {
					if err := os.Chtimes(filepath.Join(base, entry), now, now); err != nil {
						t.Fatal(err)
					}
				}
			},
			// Opening a compilation cache store grows its files to their mapped
			// size, and closing it truncates them back.
			"compilation cache opened": func(t *testing.T, base string) {
				path := filepath.Join(base, "data", "plugin", "v1.1", "index.v1")
				if err := os.Truncate(path, 1<<20); err != nil {
					t.Fatal(err)
				}
				if err := os.Truncate(path, int64(len("index"))); err != nil {
					t.Fatal(err)
				}
			},
			// A run's result bundle lives until its upload deletes it.
			"result bundle uploaded": func(t *testing.T, base string) {
				writeVolumeFile(t, base, "data/tuist/Runs/0c9a/bundle", "result")
				if err := os.RemoveAll(filepath.Join(base, "data", "tuist", "Runs")); err != nil {
					t.Fatal(err)
				}
			},
			"generation recorded": func(t *testing.T, base string) {
				writeVolumeFile(t, base, "data/tuist/GenerationMetadata/cfbc.json", `{"generationId":"bbbb"}`)
			},
			"retention swept": func(t *testing.T, base string) {
				writeVolumeFile(t, base, "data/tuist/.support-cache-sweep", "")
			},
		} {
			t.Run(key+"/"+name, func(t *testing.T) {
				share, mount, base := mountedVolumeWithKey(t, key, managedSeed)
				use(t, base)

				if reportedChange(t, share, mount) {
					t.Fatal("a volume the job only read was reported as changed")
				}
			})
		}
	}
}

func TestMacReportsContentChangesToAManagedVolume(t *testing.T) {
	for name, change := range map[string]func(t *testing.T, base string){
		"binary stored": func(t *testing.T, base string) {
			writeVolumeFile(t, base, "data/tuist/Binaries/9a8b/Feature.xcframework/Info.plist", "plist")
		},
		"binary evicted": func(t *testing.T, base string) {
			_ = os.RemoveAll(filepath.Join(base, "data", "tuist", "Binaries", "1f2e"))
		},
		"objects stored":  func(t *testing.T, base string) { writeVolumeFile(t, base, "data/plugin/v1.1/data.v1", "data and more") },
		"store rotated":   func(t *testing.T, base string) { writeVolumeFile(t, base, "data/plugin/v1.2/data.v1", "data") },
		"store pruned":    func(t *testing.T, base string) { _ = os.RemoveAll(filepath.Join(base, "data", "plugin", "v1.1")) },
		"manifest cached": func(t *testing.T, base string) { writeVolumeFile(t, base, "data/tuist/Manifests/1.77aa", "manifest") },
		"framework linked": func(t *testing.T, base string) {
			if err := os.Symlink("Versions/Current/Core", filepath.Join(base, "data", "tuist", "Binaries", "1f2e", "Core")); err != nil {
				t.Fatal(err)
			}
		},
		"path attached": func(t *testing.T, base string) { writeVolumeFile(t, base, digest("second")+"/file", "new") },
	} {
		t.Run(name, func(t *testing.T) {
			share, mount, base := mountedVolumeWithKey(t, "tuist-module", managedSeed)
			change(t, base)

			if !reportedChange(t, share, mount) {
				t.Fatal("a changed volume was reported as unchanged")
			}
		})
	}
}

func TestMacStillReportsATouchedCustomVolumeAsChanged(t *testing.T) {
	share, mount, base := mountedVolume(t, map[string]string{"data/dependency.jar": "saved"})
	now := time.Now()
	if err := os.Chtimes(filepath.Join(base, "data", "dependency.jar"), now, now); err != nil {
		t.Fatal(err)
	}

	if !reportedChange(t, share, mount) {
		t.Fatal("a custom volume whose file was touched was reported as unchanged")
	}
}

func TestMacMeasuresAManagedVolumeAgainOnceItsHoldersAreReleased(t *testing.T) {
	share, mount, base := mountedVolumeWithKey(t, "tuist-xcode", managedSeed)
	index := filepath.Join(base, "data", "plugin", "v1.1", "index.v1")
	// A process that still has the store open keeps its files at their mapped size.
	if err := os.Truncate(index, 1<<20); err != nil {
		t.Fatal(err)
	}
	busy := true
	detach := func(args ...string) error {
		if args[0] == "detach" && busy {
			return errors.New("resource busy")
		}
		return nil
	}
	release := func(string, bool) {
		busy = false
		if err := os.Truncate(index, int64(len("index"))); err != nil {
			t.Fatal(err)
		}
	}
	if err := detachMacAt(share, mount, detach, fakeMacMeasure, release, func() {}); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(filepath.Join(share, digest("volume"), ".usage"))
	if err != nil {
		t.Fatal(err)
	}
	var usage struct {
		Changed bool `json:"changed"`
	}
	if err = json.Unmarshal(data, &usage); err != nil {
		t.Fatal(err)
	}
	if usage.Changed {
		t.Fatal("the volume was measured while a released holder still had it open")
	}
}
