package main

import (
	"archive/tar"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func linuxCheckoutFixture(t *testing.T) (root, workspace string) {
	t.Helper()
	work := t.TempDir()
	return filepath.Join(work, "_tuist_cache"), filepath.Join(work, "repo", "repo")
}

func answer(response macResponse) func(context.Context) (macResponse, error) {
	return func(context.Context) (macResponse, error) { return response, nil }
}

func TestLinuxCheckoutStateIsRecordedOnlyWithAGrant(t *testing.T) {
	never := func(string, string, string, string) error { t.Fatal("mounted without a checkout"); return nil }
	for reason, recorded := range map[string]bool{"cold": true, "capacity": true, "timeout": true, "denied": false, "error": false} {
		root, workspace := linuxCheckoutFixture(t)
		state := filepath.Join(t.TempDir(), "state.json")
		result := checkoutLinuxAt(context.Background(), workspace, root, state, answer(macResponse{Error: "unavailable", Reason: reason}), never)
		if result != "unavailable ("+reason+")" {
			t.Errorf("reason %q: %s", reason, result)
		}
		if _, err := os.Stat(state); (err == nil) != recorded {
			t.Errorf("reason %q: state recorded %v, want %v", reason, err == nil, recorded)
		}
	}
}

func TestLinuxCheckoutMountsTheHostsCloneAtTheWorkspace(t *testing.T) {
	root, workspace := linuxCheckoutFixture(t)
	scope := strings.Repeat("a", 64)
	id := "11111111-1111-4111-8111-111111111111"
	base := strings.Repeat("b", 40)
	writeFile(t, filepath.Join(root, scope, ".tuist-volume"), id)
	writeFile(t, filepath.Join(root, scope, "checkout", ".git", "HEAD"), base+"\n")
	state := filepath.Join(t.TempDir(), "state.json")
	var calls []string
	mount := func(socket, source, relative, target string) error {
		calls = append(calls, socket, source, relative, target)
		// The broker binds the working tree; mimic what the workspace then shows.
		writeFile(t, filepath.Join(target, ".git", "HEAD"), base+"\n")
		return nil
	}
	result := checkoutLinuxAt(context.Background(), workspace, root, state, answer(macResponse{ID: id, Directory: scope, Warm: true}), mount)
	if result != "reused" {
		t.Fatal(result)
	}
	want := []string{filepath.Join(filepath.Dir(root), ".tuist-cache-mount.sock"), scope + "/checkout", "repo/repo", workspace}
	if strings.Join(calls, "|") != strings.Join(want, "|") {
		t.Fatalf("mounted %v, want %v", calls, want)
	}
	var recorded checkoutState
	data, _ := os.ReadFile(state)
	if err := json.Unmarshal(data, &recorded); err != nil || recorded.Workspace != workspace || recorded.Base != base {
		t.Fatalf("state %s %v", data, err)
	}
}

func TestLinuxCheckoutLeavesTheWorkspaceAloneWithoutProof(t *testing.T) {
	never := func(string, string, string, string) error { t.Fatal("mounted"); return nil }
	scope := strings.Repeat("a", 64)
	response := macResponse{ID: "11111111-1111-4111-8111-111111111111", Directory: scope}

	root, workspace := linuxCheckoutFixture(t)
	writeFile(t, filepath.Join(root, scope, ".tuist-volume"), "another use")
	if result := checkoutLinuxAt(context.Background(), workspace, root, filepath.Join(t.TempDir(), "s"), answer(response), never); result != "unavailable (not mounted)" {
		t.Fatal(result)
	}

	root, workspace = linuxCheckoutFixture(t)
	writeFile(t, filepath.Join(workspace, "existing"), "")
	if result := checkoutLinuxAt(context.Background(), workspace, root, filepath.Join(t.TempDir(), "s"), answer(response), never); result != "skipped (workspace is not empty)" {
		t.Fatal(result)
	}

	root, _ = linuxCheckoutFixture(t)
	for _, outside := range []string{"/etc/repo", filepath.Join(root, scope), filepath.Dir(root)} {
		if result := checkoutLinuxAt(context.Background(), outside, root, filepath.Join(t.TempDir(), "s"), answer(response), never); !strings.HasPrefix(result, "skipped") {
			t.Fatalf("%s: %s", outside, result)
		}
	}

	root, workspace = linuxCheckoutFixture(t)
	failing := func(context.Context) (macResponse, error) { return macResponse{}, errors.New("unreachable") }
	state := filepath.Join(t.TempDir(), "s")
	if result := checkoutLinuxAt(context.Background(), workspace, root, state, failing, never); result != "unavailable (request)" {
		t.Fatal(result)
	}
	if _, err := os.Stat(state); !os.IsNotExist(err) {
		t.Fatal("recorded state without a grant")
	}
}

func TestLinuxCheckoutExportStreamsTheExportAndCleansUp(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("requires git")
	}
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
	writeFile(t, filepath.Join(workspace, "file.txt"), "content")
	git("add", ".")
	git("commit", "-q", "-m", "job")
	head := git("rev-parse", "HEAD")
	oid := strings.Repeat("3", 64)
	writeFile(t, filepath.Join(workspace, ".git", "lfs", "objects", "33", "33", oid), "object")
	state := filepath.Join(t.TempDir(), "state.json")
	if err := recordCheckout(state, workspace, false); err != nil {
		t.Fatal(err)
	}
	scratch := filepath.Join(t.TempDir(), "export")
	entries := map[string]string{}
	upload := func(_ context.Context, body io.Reader) error {
		archive := tar.NewReader(body)
		for {
			header, err := archive.Next()
			if errors.Is(err, io.EOF) {
				return nil
			}
			if err != nil {
				return err
			}
			data, _ := io.ReadAll(archive)
			entries[header.Name] = string(data)
		}
	}
	result := exportCheckoutLinuxAt(context.Background(), state, scratch, gitCommand, upload)
	if !strings.HasPrefix(result, "exported") {
		t.Fatal(result)
	}
	if strings.TrimSpace(entries["head"]) != head || entries["pack"] == "" || entries["lfs/"+oid] != "object" || len(entries) != 3 {
		t.Fatalf("streamed %v", entries)
	}
	if _, err := os.Stat(scratch); !os.IsNotExist(err) {
		t.Fatal("left the export behind")
	}
	if data, err := os.ReadFile(filepath.Join(workspace, ".git", "lfs", "objects", "33", "33", oid)); err != nil || string(data) != "object" {
		t.Fatal("the export changed the job's LFS object")
	}

	failed := exportCheckoutLinuxAt(context.Background(), state, scratch, gitCommand, func(context.Context, io.Reader) error { return errors.New("host refused") })
	if failed != "failed (host refused)" {
		t.Fatal(failed)
	}
}
