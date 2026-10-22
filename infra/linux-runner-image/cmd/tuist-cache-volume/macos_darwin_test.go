package main

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/sys/unix"
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
	if _, _, _, err := acquireMacAt(context.Background(), "key", 0, share, mountRoot, realAttach); err != nil {
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
	if _, _, _, err := acquireMacAt(context.Background(), "key", 0, share, mountRoot, realAttach); err != nil {
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

func realAttach(image, mountPoint string) error {
	ctx := context.Background()
	return attachMacVolume(ctx, image, mountPoint, macRun, func(args ...string) error { return macCommandContext(ctx, args...) })
}

func TestMacRealAttachGrowsTheContainerToTheEnlargedImage(t *testing.T) {
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
	seed := t.TempDir()
	if err := command("attach", image, "-quiet", "-nobrowse", "-mountpoint", seed); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(seed, "dependency"), []byte("retained"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := command("detach", seed, "-quiet"); err != nil {
		t.Fatal(err)
	}
	if err := command("resize", "-size", "300m", "-imageonly", image); err != nil {
		t.Fatal(err)
	}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	mount := filepath.Join(mountRoot, response.Directory)
	t.Cleanup(func() { _ = command("detach", mount, "-force", "-quiet") })
	if _, _, _, err := acquireMacAt(context.Background(), "key", 300_000_000, share, mountRoot, realAttach); err != nil {
		t.Fatal(err)
	}
	if _, capacity, err := measureMac(mount); err != nil || capacity < 250_000_000 {
		t.Fatalf("container did not grow: capacity %d, %v", capacity, err)
	}
	payload, err := os.ReadFile(filepath.Join(mount, "dependency"))
	if err != nil || string(payload) != "retained" {
		t.Fatalf("contents did not survive growth: %v", err)
	}
	if err := detachMacAt(share, mountRoot, command, measureMac, func(string, bool) {}, func() {}); err != nil {
		t.Fatal(err)
	}
}

func TestMacRealCheckoutKeepsTheVolumeRootOutsideTheWorkspace(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git is not installed")
	}
	share := t.TempDir()
	t.Setenv("RUNNER_TRACKING_ID", "tuist-cache-test-"+digest(share))
	response := macResponse{Directory: digest("checkout"), ID: "lease"}
	shared := filepath.Join(share, response.Directory)
	if err := os.Mkdir(shared, 0755); err != nil {
		t.Fatal(err)
	}
	command := func(args ...string) error { return macCommandContext(context.Background(), args...) }
	image := filepath.Join(shared, "cache.sparseimage")
	if err := command("create", "-quiet", "-size", "100m", "-type", "SPARSE", "-fs", "APFS", "-volname", "TuistCheckoutTest", image); err != nil {
		t.Fatal(err)
	}
	// The host writes the tree at the image's root, configured as it configures masters.
	host := t.TempDir()
	if err := command("attach", image, "-quiet", "-nobrowse", "-mountpoint", host); err != nil {
		t.Fatal(err)
	}
	git := func(dir string, args ...string) string {
		t.Helper()
		out, err := exec.Command("git", append([]string{"-C", dir, "-c", "user.name=t", "-c", "user.email=t@t"}, args...)...).CombinedOutput()
		if err != nil {
			t.Fatal(err, string(out))
		}
		return string(out)
	}
	git(host, "init", "-q", ".")
	git(host, "config", "core.checkStat", "minimal")
	git(host, "config", "core.trustctime", "false")
	writeFile(t, filepath.Join(host, "README.md"), "readme")
	writeFile(t, filepath.Join(host, "repo", "App.swift"), "app")
	git(host, "add", ".")
	git(host, "commit", "-q", "-m", "tree")
	if err := command("detach", host, "-quiet"); err != nil {
		t.Fatal(err)
	}

	parent := filepath.Join(t.TempDir(), "repo")
	workspace := filepath.Join(parent, "repo")
	if err := os.MkdirAll(workspace, 0755); err != nil {
		t.Fatal(err)
	}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	t.Cleanup(func() { _ = command("detach", parent, "-force", "-quiet") })
	if result := checkoutMacAt(context.Background(), workspace, share, filepath.Join(t.TempDir(), "state.json"), command); result != "reused" {
		t.Fatal(result)
	}
	var workspaceStat, parentStat, aboveStat unix.Stat_t
	for path, stat := range map[string]*unix.Stat_t{workspace: &workspaceStat, parent: &parentStat, filepath.Dir(parent): &aboveStat} {
		if err := unix.Stat(path, stat); err != nil {
			t.Fatal(err)
		}
	}
	if workspaceStat.Dev != parentStat.Dev || parentStat.Dev == aboveStat.Dev {
		t.Fatal("the workspace is not inside the volume mounted at its parent")
	}
	if status := git(workspace, "status", "--porcelain", "--untracked-files=all"); status != "" {
		t.Fatalf("the moved tree is not clean:\n%s", status)
	}
	// An index the move left valid lists no entry as stat-dirty.
	if dirty := git(workspace, "diff-files", "--name-only"); dirty != "" {
		t.Fatalf("the move invalidated index entries:\n%s", dirty)
	}
}
