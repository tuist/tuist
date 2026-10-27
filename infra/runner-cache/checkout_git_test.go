package cachevolumes

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestCheckoutGitRepackInheritsMemoryLimitsWithoutChangingGuestConfig(t *testing.T) {
	gitPath, err := exec.LookPath("git")
	if err != nil {
		t.Skip("git is not installed")
	}
	ctx := context.Background()
	c := &Checkouts{Root: t.TempDir(), Path: filepath.Dir(gitPath) + ":/usr/bin:/bin"}
	repo := t.TempDir()
	run := func(env []string, args ...string) []byte {
		t.Helper()
		out, err := c.run(ctx, repo, env, "git", args...)
		if err != nil {
			t.Fatal(err)
		}
		return out
	}
	run(c.baseEnv(), "init", "-q")
	// Repository settings must not defeat the host's budget or be overwritten
	// by it: jobs receive this config with their clone of the master.
	run(c.baseEnv(), "config", "pack.threads", "8")
	run(c.baseEnv(), "config", "pack.windowMemory", "0")
	configPath := filepath.Join(repo, ".git", "config")
	before, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, filepath.Join(repo, "payload"), strings.Repeat("payload\n", 1024))
	run(c.gitEnv(), "add", "payload")
	run(c.gitEnv(), "-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-qm", "fixture")
	trace := filepath.Join(t.TempDir(), "trace.json")
	env := append(c.gitEnv(), "GIT_TRACE2_EVENT="+trace, "GIT_TRACE2_CONFIG_PARAMS=pack.threads,pack.windowMemory,pack.deltaCacheSize,core.deltaBaseCacheLimit,core.bigFileThreshold,core.packedGitWindowSize,core.packedGitLimit")
	run(env, "repack", "-adf")
	data, err := os.ReadFile(trace)
	if err != nil {
		t.Fatal(err)
	}
	children := map[string]map[string]string{}
	packChild := ""
	for _, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
		var event struct {
			Event, Sid, Name, Param, Value, Scope string
		}
		if err := json.Unmarshal([]byte(line), &event); err != nil {
			t.Fatal(err)
		}
		if event.Event == "cmd_name" && event.Name == "pack-objects" {
			packChild = event.Sid
		}
		if event.Event == "def_param" && event.Scope == "command" {
			if children[event.Sid] == nil {
				children[event.Sid] = map[string]string{}
			}
			children[event.Sid][event.Param] = event.Value
		}
	}
	for key, want := range map[string]string{
		"pack.threads": "1", "pack.windowmemory": "32m", "pack.deltacachesize": "16m",
		"core.deltabasecachelimit": "16m", "core.bigfilethreshold": "16m",
		"core.packedgitwindowsize": "16m", "core.packedgitlimit": "64m",
	} {
		if got := children[packChild][key]; packChild == "" || got != want {
			t.Fatalf("pack-objects did not inherit %s=%s: child=%q got=%q\n%s", key, want, packChild, got, data)
		}
	}
	packs, err := filepath.Glob(filepath.Join(repo, ".git", "objects", "pack", "*.pack"))
	if err != nil || len(packs) != 1 {
		t.Fatalf("repack: %v, %v", packs, err)
	}
	run(c.gitEnv(), "index-pack", "--strict", packs[0])
	run(c.gitEnv(), "fsck", "--strict", "--no-dangling")
	pack, err := os.ReadFile(packs[0])
	if err != nil {
		t.Fatal(err)
	}
	pack[len(pack)-1] ^= 1
	corrupt := filepath.Join(t.TempDir(), "corrupt.pack")
	if err := os.WriteFile(corrupt, pack, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := c.run(ctx, repo, c.gitEnv(), "git", "index-pack", "--strict", corrupt); err == nil {
		t.Fatal("accepted a corrupt pack with the host memory limits")
	}
	after, err := os.ReadFile(configPath)
	if err != nil || string(before) != string(after) {
		t.Fatalf("host limits changed the guest config: %s, %v", after, err)
	}
}
