package main

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestCheckoutStateIsRecordedOnlyWithAGrant(t *testing.T) {
	never := func(...string) error { t.Fatal("attached without a checkout"); return nil }
	for reason, recorded := range map[string]bool{"cold": true, "capacity": true, "timeout": true, "denied": false, "error": false} {
		share := t.TempDir()
		state := filepath.Join(t.TempDir(), "state.json")
		data, _ := json.Marshal(macResponse{Error: "unavailable", Reason: reason})
		respondMac(t, share, data)
		checkoutMacAt(context.Background(), filepath.Join(t.TempDir(), "repo"), share, state, never)
		if _, err := os.Stat(state); (err == nil) != recorded {
			t.Errorf("reason %q: state recorded %v, want %v", reason, err == nil, recorded)
		}
	}
}

func TestCheckoutStateRemembersTheMountedMaster(t *testing.T) {
	workspace := t.TempDir()
	base := strings.Repeat("a", 40)
	oid := strings.Repeat("b", 64)
	writeFile(t, filepath.Join(workspace, ".git", "HEAD"), base+"\n")
	writeFile(t, filepath.Join(workspace, ".git", "lfs", "objects", "bb", "bb", oid), "object")
	path := filepath.Join(t.TempDir(), "state.json")
	if err := recordCheckout(path, workspace, true); err != nil {
		t.Fatal(err)
	}
	var state checkoutState
	data, _ := os.ReadFile(path)
	if err := json.Unmarshal(data, &state); err != nil {
		t.Fatal(err)
	}
	if state.Workspace != workspace || state.Base != base || len(state.LFS) != 1 || filepath.Base(state.LFS[0]) != oid {
		t.Fatalf("%+v", state)
	}
}

func TestCheckoutExportCarriesOnlyWhatTheJobAdded(t *testing.T) {
	workspace := t.TempDir()
	git := func(args ...string) string {
		t.Helper()
		command := exec.Command("git", args...)
		command.Dir = workspace
		command.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
		out, err := command.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v %s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	git("init", "-q", ".")
	writeFile(t, filepath.Join(workspace, "old.txt"), "old")
	git("add", ".")
	git("commit", "-q", "-m", "base")
	base := git("rev-parse", "HEAD")
	old := strings.Repeat("1", 64)
	writeFile(t, filepath.Join(workspace, ".git", "lfs", "objects", "11", "11", old), "old object")
	state := filepath.Join(t.TempDir(), "state.json")
	if err := recordCheckout(state, workspace, false); err != nil {
		t.Fatal(err)
	}
	// What a mounted master would have recorded: its commit and its LFS objects.
	data, _ := json.Marshal(checkoutState{Workspace: workspace, Base: base, LFS: []string{filepath.Join("11", "11", old)}})
	writeFile(t, state, string(data))
	writeFile(t, filepath.Join(workspace, "new.txt"), "new")
	git("add", ".")
	git("commit", "-q", "-m", "job")
	head := git("rev-parse", "HEAD")
	added := strings.Repeat("2", 64)
	writeFile(t, filepath.Join(workspace, ".git", "lfs", "objects", "22", "22", added), "new object")

	share := t.TempDir()
	result := exportCheckoutAt(context.Background(), state, share, gitCommand)
	if !strings.HasPrefix(result, "exported") {
		t.Fatal(result)
	}
	export := filepath.Join(share, "checkout-export")
	if data, _ := os.ReadFile(filepath.Join(export, "head")); strings.TrimSpace(string(data)) != head {
		t.Fatalf("head %q", data)
	}
	if entries, _ := os.ReadDir(filepath.Join(export, "lfs")); len(entries) != 1 || entries[0].Name() != added {
		t.Fatalf("exported LFS objects %v", entries)
	}
	pack := filepath.Join(t.TempDir(), "export.pack")
	if err := copyFile(filepath.Join(export, "pack"), pack); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command("git", "index-pack", pack).CombinedOutput(); err != nil {
		t.Fatalf("%v %s", err, out)
	}
	out, err := exec.Command("git", "verify-pack", "-v", strings.TrimSuffix(pack, ".pack")+".idx").CombinedOutput()
	if err != nil {
		t.Fatalf("%v %s", err, out)
	}
	listing := string(out)
	if !strings.Contains(listing, head) || strings.Contains(listing, base) {
		t.Fatalf("the pack must hold the job's commit and nothing the master had:\n%s", listing)
	}
	if _, err := os.Stat(filepath.Join(share, ".checkout-export.tmp")); !os.IsNotExist(err) {
		t.Fatal("left the temporary export behind")
	}
}

func TestCheckoutExportSkipsWithoutAGrantOrARepository(t *testing.T) {
	share := t.TempDir()
	if result := exportCheckoutAt(context.Background(), filepath.Join(t.TempDir(), "missing.json"), share, gitCommand); !strings.HasPrefix(result, "skipped") {
		t.Fatal(result)
	}
	state := filepath.Join(t.TempDir(), "state.json")
	if err := recordCheckout(state, t.TempDir(), false); err != nil {
		t.Fatal(err)
	}
	if result := exportCheckoutAt(context.Background(), state, share, gitCommand); !strings.HasPrefix(result, "skipped") {
		t.Fatal(result)
	}
	if _, err := os.Stat(filepath.Join(share, "checkout-export")); !os.IsNotExist(err) {
		t.Fatal("exported without a repository")
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}
