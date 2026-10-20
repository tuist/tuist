package main

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
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
	if err := detachMacAt(share, mountRoot, command, measureMac, func(string, bool) {}, func() {}); err != nil {
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

func TestMacRealDetachEndsAProcessRunningFromTheVolume(t *testing.T) {
	share, mountRoot := t.TempDir(), t.TempDir()
	t.Setenv("RUNNER_TRACKING_ID", "tuist-cache-test-"+digest(share))
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
	t.Cleanup(func() { _ = command("detach", mount, "-force", "-quiet") })
	if _, _, _, err := acquireMacAt(context.Background(), "key", share, mountRoot, command); err != nil {
		t.Fatal(err)
	}
	source := t.TempDir()
	program := "package main\n\nimport \"time\"\n\nfunc main() { time.Sleep(10 * time.Minute) }\n"
	_ = os.WriteFile(filepath.Join(source, "go.mod"), []byte("module holder\n"), 0644)
	_ = os.WriteFile(filepath.Join(source, "main.go"), []byte(program), 0644)
	installed := filepath.Join(mount, "installs", "holder")
	build := exec.Command("go", "build", "-o", installed, ".")
	build.Dir, build.Env = source, append(os.Environ(), "GOWORK=off")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatal(err, string(out))
	}
	holder := exec.Command(installed)
	if err := holder.Start(); err != nil {
		t.Fatal(err)
	}
	exited := make(chan struct{})
	go func() { _ = holder.Wait(); close(exited) }()
	t.Cleanup(func() { _ = holder.Process.Kill() })
	if err := command("detach", mount, "-quiet"); err == nil {
		t.Fatal("detached a volume a process is running from")
	}
	release := func(base string, kill bool) { releaseMac(context.Background(), base, kill) }
	if err := detachMacAt(share, mountRoot, command, measureMac, release, func() { time.Sleep(time.Second) }); err != nil {
		t.Fatal(err)
	}
	select {
	case <-exited:
	default:
		t.Fatal("holder still running")
	}
	proof, err := os.ReadFile(filepath.Join(shared, ".detached"))
	if err != nil || string(proof) != response.ID {
		t.Fatalf("missing clean detach proof: %v", err)
	}
}
