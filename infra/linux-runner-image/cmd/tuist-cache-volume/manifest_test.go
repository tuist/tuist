package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// attachLayout attaches targets to the volume at base and returns the
// subdirectory each target mounted, keyed by its spelling.
func attachLayout(t *testing.T, base string, targets ...string) map[string]string {
	t.Helper()
	workspace := t.TempDir()
	t.Chdir(workspace)
	cache := filepath.Dir(base)
	sources := map[string]string{}
	mounted := map[string]string{}
	err := attachUsing("key", targets, cache, func() (string, string, bool, error) {
		return filepath.Base(base), "lease", true, nil
	}, func(_ string, source, target string) error {
		sources[target] = filepath.Base(source)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, target := range targets {
		mounted[target] = sources[filepath.Join(workspace, target)]
	}
	return mounted
}

func newVolume(t *testing.T) string {
	t.Helper()
	base := filepath.Join(t.TempDir(), digest("volume"))
	if err := os.MkdirAll(base, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(base, ".tuist-volume"), []byte("lease"), 0644); err != nil {
		t.Fatal(err)
	}
	return base
}

func manifestPaths(t *testing.T, base string) map[string]string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(base, manifestName))
	if err != nil {
		t.Fatal(err)
	}
	var manifest pathManifest
	if err := json.Unmarshal(data, &manifest); err != nil || manifest.Version != 1 {
		t.Fatalf("invalid manifest %s: %v", data, err)
	}
	return manifest.Paths
}

func TestManifestKeepsDataWhenPathsAreAddedAndRemoved(t *testing.T) {
	base := newVolume(t)
	if got := attachLayout(t, base, ".npm"); got[".npm"] != "data" {
		t.Fatal(got)
	}
	got := attachLayout(t, base, ".npm", ".build")
	if got[".npm"] != "data" || got[".build"] != digest(".build") {
		t.Fatal(got)
	}
	if got := attachLayout(t, base, ".build", "./.npm/"); got["./.npm/"] != "data" || got[".build"] != digest(".build") {
		t.Fatal("a reordered list moved data:", got)
	}
	if got := attachLayout(t, base, ".npm"); got[".npm"] != "data" {
		t.Fatal(got)
	}
	if got := attachLayout(t, base, ".build"); got[".build"] != digest(".build") {
		t.Fatal(got)
	}
	if paths := manifestPaths(t, base); fmt.Sprint(paths) != fmt.Sprint(map[string]string{".npm": "data", ".build": digest(".build")}) {
		t.Fatal(paths)
	}
}

func TestManifestKeepsASinglePathsDataWhenItIsRenamed(t *testing.T) {
	base := newVolume(t)
	attachLayout(t, base, ".npm")
	if got := attachLayout(t, base, "cache/.npm"); got["cache/.npm"] != "data" {
		t.Fatal(got)
	}
	if paths := manifestPaths(t, base); fmt.Sprint(paths) != fmt.Sprint(map[string]string{"cache/.npm": "data"}) {
		t.Fatal(paths)
	}
	if got := attachLayout(t, base, ".npm", ".build"); got[".npm"] != digest(".npm") {
		t.Fatal("handed the data of the renamed path to its old spelling:", got)
	}
}

func TestManifestRecordsAPreManifestSinglePathVolume(t *testing.T) {
	base := newVolume(t)
	writeVolumeFile(t, base, "data/package", "saved")
	if got := attachLayout(t, base, ".npm"); got[".npm"] != "data" {
		t.Fatal(got)
	}
	if paths := manifestPaths(t, base); paths[".npm"] != "data" || len(paths) != 1 {
		t.Fatal(paths)
	}
	if got := attachLayout(t, base, ".npm", ".build"); got[".npm"] != "data" {
		t.Fatal(got)
	}
}

func TestManifestStartsEveryPathColdWhenAPreManifestVolumeGetsSeveralPaths(t *testing.T) {
	base := newVolume(t)
	writeVolumeFile(t, base, "data/package", "saved")
	got := attachLayout(t, base, ".npm", ".build")
	if got[".npm"] != digest(".npm") || got[".build"] != digest(".build") {
		t.Fatal(got)
	}
	if got := attachLayout(t, base, ".yarn"); got[".yarn"] != "data" {
		t.Fatal("a single path did not mount data:", got)
	}
}

func TestManifestIsOnlyWrittenWhenTheLayoutChanges(t *testing.T) {
	base := newVolume(t)
	attachLayout(t, base, ".npm", ".build")
	manifest := filepath.Join(base, manifestName)
	earlier := time.Now().Add(-time.Hour)
	if err := os.Chtimes(manifest, earlier, earlier); err != nil {
		t.Fatal(err)
	}
	attachLayout(t, base, ".build", ".npm")
	attachLayout(t, base, ".npm")
	info, err := os.Stat(manifest)
	if err != nil || !info.ModTime().Equal(earlier) {
		t.Fatal("rewrote an unchanged manifest", err)
	}
	entries, _ := os.ReadDir(base)
	for _, entry := range entries {
		if entry.Name() != ".tuist-volume" && entry.Name() != manifestName && entry.Name() != digest(".npm") && entry.Name() != digest(".build") {
			t.Fatal("unexpected entry", entry.Name())
		}
	}
}

func TestManifestIgnoresAndRewritesAMalformedManifest(t *testing.T) {
	for name, contents := range map[string]string{
		"not json":        "{",
		"unknown version": `{"version":2,"paths":{".npm":"data"}}`,
		"foreign entry":   `{"version":1,"paths":{".npm":"` + digest(".yarn") + `"}}`,
		"double data":     `{"version":1,"paths":{".npm":"data",".yarn":"data"}}`,
	} {
		t.Run(name, func(t *testing.T) {
			base := newVolume(t)
			writeVolumeFile(t, base, manifestName, contents)
			got := attachLayout(t, base, ".npm", ".gradle")
			if got[".npm"] != digest(".npm") || got[".gradle"] != digest(".gradle") {
				t.Fatal(got)
			}
			paths := manifestPaths(t, base)
			if paths[".npm"] != digest(".npm") || paths[".gradle"] != digest(".gradle") {
				t.Fatal(paths)
			}
		})
	}
}
