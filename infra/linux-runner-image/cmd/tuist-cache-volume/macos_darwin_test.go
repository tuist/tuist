package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestMacRealAttachAndCleanDetach(t *testing.T) {
	share, mountRoot := t.TempDir(), t.TempDir()
	tracking := "tuist-cache-test-" + digest(share)
	t.Setenv("RUNNER_TRACKING_ID", tracking)
	response := macResponse{Directory: digest("volume"), ID: "lease"}
	shared := filepath.Join(share, response.Directory)
	if err := os.Mkdir(shared, 0755); err != nil {
		t.Fatal(err)
	}
	command := func(args ...string) error { return macCommandContext(context.Background(), args...) }
	image := filepath.Join(shared, "cache.sparseimage")
	if err := command("create", "-quiet", "-size", "100m", "-type", "SPARSE", "-fs", "APFS", "-volname", "TuistCacheTest", image); err != nil {
		t.Fatal(err)
	}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	mount := filepath.Join(mountRoot, response.Directory)
	t.Cleanup(func() { _ = command("detach", mount, "-quiet") })
	if _, _, _, err := acquireMacAt(context.Background(), "key", share, mountRoot, command); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mount, "dependency"), []byte("retained"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := detachMacAt(share, mountRoot, command, measureMac, func() {}); err != nil {
		t.Fatal(err)
	}
	proof, err := os.ReadFile(filepath.Join(shared, ".detached"))
	if err != nil || string(proof) != response.ID {
		t.Fatalf("missing clean detach proof: %v", err)
	}
	if err := command("attach", image, "-quiet", "-nobrowse", "-mountpoint", mount); err != nil {
		t.Fatal(err)
	}
	payload, err := os.ReadFile(filepath.Join(mount, "dependency"))
	if err != nil || string(payload) != "retained" {
		t.Fatalf("dependency did not survive clean detach: %v", err)
	}
}
