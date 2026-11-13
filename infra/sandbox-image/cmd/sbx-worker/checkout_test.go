package main

import (
	"archive/tar"
	"bufio"
	"bytes"
	"context"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func gitIn(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t", "GIT_CONFIG_NOSYSTEM=1", "HOME="+t.TempDir())
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func commitFiles(t *testing.T, repo string, files map[string]string) string {
	t.Helper()
	for name, content := range files {
		if err := os.MkdirAll(filepath.Dir(filepath.Join(repo, name)), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(repo, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	gitIn(t, repo, "add", "-A")
	gitIn(t, repo, "commit", "-q", "-m", "c")
	return gitIn(t, repo, "rev-parse", "HEAD")
}

// tarDir streams a directory the way the Linux host streams a master.
func tarDir(t *testing.T, dir string, w io.Writer) {
	t.Helper()
	archive := tar.NewWriter(w)
	if err := archive.AddFS(os.DirFS(dir)); err != nil {
		t.Fatal(err)
	}
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
}

// fakeHost answers one vsock connection per call with serve.
func fakeHost(serve func(op string, r *bufio.Reader, w net.Conn)) func(uint32) (net.Conn, error) {
	return func(uint32) (net.Conn, error) {
		guest, host := net.Pipe()
		go func() {
			defer host.Close()
			r := bufio.NewReader(host)
			line, err := r.ReadString('\n')
			if err != nil {
				return
			}
			serve(strings.TrimSpace(line), r, host)
		}()
		return guest, nil
	}
}

// A session starts from the master's tree and later exports only the objects
// of the grant's commit that the master lacks, whatever branch it ends on.
func TestCheckoutSeedsFromHostAndExportsOnlyTheGrantedCommit(t *testing.T) {
	origin := t.TempDir()
	gitIn(t, origin, "init", "-q", "-b", "main")
	base := commitFiles(t, origin, map[string]string{"README": "one\n", "src/a.txt": "a\n"})
	master := t.TempDir()
	gitIn(t, master, "clone", "-q", "--depth", "1", "file://"+origin, "repo")
	granted := commitFiles(t, origin, map[string]string{"src/b.txt": "b\n", "src/a.txt": "a2\n"})

	baseDir := t.TempDir()
	path := filepath.Join(baseDir, "acme", "app")
	t.Setenv(checkoutPathEnv, path)
	t.Setenv(checkoutCommitEnv, granted)
	t.Setenv(checkoutVsockEnv, "5002")
	checkout, err := checkoutFromEnv(baseDir, nil)
	if err != nil || checkout == nil {
		t.Fatalf("checkoutFromEnv = %v, %v", checkout, err)
	}
	var export bytes.Buffer
	var packData []byte
	checkout.dial = fakeHost(func(op string, r *bufio.Reader, w net.Conn) {
		switch op {
		case `{"op":"seed"}`:
			_, _ = io.WriteString(w, `{"ok":true}`+"\n")
			tarDir(t, filepath.Join(master, "repo"), w)
		case `{"op":"export"}`:
			archive := tar.NewReader(r)
			for {
				header, err := archive.Next()
				if err != nil {
					break
				}
				data, _ := io.ReadAll(archive)
				export.WriteString(header.Name + "\n")
				if header.Name == "head" || header.Name == "shallow" {
					export.Write(data)
				}
				if header.Name == "pack" {
					packData = data
				}
			}
			_, _ = io.WriteString(w, `{"ok":true}`+"\n")
		}
	})

	if result, err := checkout.seed(context.Background()); err != nil || result != "warm" {
		t.Fatalf("seed = %q, %v", result, err)
	}
	if got := gitIn(t, path, "rev-parse", "HEAD"); got != base {
		t.Fatalf("seeded HEAD = %s, want the master's %s", got, base)
	}
	// A resumed sandbox keeps the session's repository.
	if result, err := checkout.seed(context.Background()); err != nil || result != "present" {
		t.Fatalf("second seed = %q, %v", result, err)
	}

	// The session fetches the default branch, then ends on a branch of its own.
	gitIn(t, path, "fetch", "-q", "file://"+origin, "main")
	gitIn(t, path, "checkout", "-q", "-b", "session", granted)
	commitFiles(t, path, map[string]string{"session.txt": "mine\n"})

	result, err := checkout.export(context.Background())
	if err != nil || !strings.HasPrefix(result, "exported "+granted[:12]) {
		t.Fatalf("export = %q, %v", result, err)
	}
	if got, want := export.String(), "head\n"+granted+"\nshallow\n"+granted+"\npack\n"; got != want {
		t.Fatalf("export entries = %q, want %q", got, want)
	}
	// The pack completes a copy of the master at the granted commit and holds
	// exactly what it lacked: the commit, the root and src trees and the two
	// new blobs, not README's blob nor anything the session wrote.
	repo := filepath.Join(t.TempDir(), "repo")
	if out, err := exec.Command("cp", "-a", filepath.Join(master, "repo"), repo).CombinedOutput(); err != nil {
		t.Fatalf("cp: %v %s", err, out)
	}
	index := exec.Command("git", "index-pack", "--stdin", "--strict")
	index.Dir = repo
	index.Stdin = bytes.NewReader(packData)
	out, err := index.CombinedOutput()
	if err != nil {
		t.Fatalf("index-pack: %v %s", err, out)
	}
	hash := strings.TrimSpace(strings.TrimPrefix(string(out), "pack\t"))
	verified := gitIn(t, repo, "verify-pack", "-v", filepath.Join(".git", "objects", "pack", "pack-"+hash+".idx"))
	count := 0
	for _, line := range strings.Split(verified, "\n") {
		if fields := strings.Fields(line); len(fields) > 1 && (fields[1] == "commit" || fields[1] == "tree" || fields[1] == "blob") {
			count++
		}
	}
	if count != 5 {
		t.Fatalf("pack holds %d objects, want 5:\n%s", count, verified)
	}
	f, err := os.OpenFile(filepath.Join(repo, ".git", "shallow"), os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = f.WriteString(granted + "\n")
	f.Close()
	gitIn(t, repo, "checkout", "-q", granted)
	if data, _ := os.ReadFile(filepath.Join(repo, "src", "a.txt")); string(data) != "a2\n" {
		t.Fatalf("a.txt = %q", data)
	}
}

// On macOS the export is left in the VM's share as the directory CI jobs leave.
func TestCheckoutExportToShareUsesTheCIFormat(t *testing.T) {
	origin := t.TempDir()
	gitIn(t, origin, "init", "-q", "-b", "main")
	commit := commitFiles(t, origin, map[string]string{"README": "one\n"})
	baseDir, share := t.TempDir(), t.TempDir()
	path := filepath.Join(baseDir, "acme", "app")
	gitIn(t, filepath.Dir(filepath.Dir(path)), "clone", "-q", "file://"+origin, filepath.Join("acme", "app"))
	if err := os.WriteFile(filepath.Join(share, checkoutImageName), []byte("clone"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv(checkoutPathEnv, path)
	t.Setenv(checkoutCommitEnv, commit)
	t.Setenv(checkoutShareEnv, share)
	checkout, err := checkoutFromEnv(baseDir, nil)
	if err != nil {
		t.Fatal(err)
	}
	// The session already has its repository: the master's clone is dropped.
	if result, err := checkout.seed(context.Background()); err != nil || result != "present" {
		t.Fatalf("seed = %q, %v", result, err)
	}
	if _, err := os.Stat(filepath.Join(share, checkoutImageName)); !os.IsNotExist(err) {
		t.Fatalf("clone left in the share: %v", err)
	}
	if _, err := checkout.export(context.Background()); err != nil {
		t.Fatal(err)
	}
	entries, _ := os.ReadDir(share)
	var names []string
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	if strings.Join(names, ",") != checkoutExportDir {
		t.Fatalf("share holds %v", names)
	}
	head, _ := os.ReadFile(filepath.Join(share, checkoutExportDir, "head"))
	if string(head) != commit+"\n" {
		t.Fatalf("head = %q", head)
	}
	if info, err := os.Stat(filepath.Join(share, checkoutExportDir, "pack")); err != nil || info.Size() == 0 {
		t.Fatalf("pack: %v", err)
	}
}

// A seed cut between entries leaves nothing behind, so the runner clones.
func TestCheckoutSeedCutShortIsDiscarded(t *testing.T) {
	var full bytes.Buffer
	archive := tar.NewWriter(&full)
	_ = archive.WriteHeader(&tar.Header{Name: "README", Mode: 0o644, Size: 3, Typeflag: tar.TypeReg})
	_, _ = archive.Write([]byte("one"))
	_ = archive.Flush()
	cut := full.Len()
	_ = archive.Close()

	dst := filepath.Join(t.TempDir(), "repo")
	if err := extractTar(bytes.NewReader(full.Bytes()[:cut]), dst); err == nil {
		t.Fatal("a stream cut between entries was accepted")
	}
	if err := extractTar(bytes.NewReader(full.Bytes()), filepath.Join(t.TempDir(), "repo")); err != nil {
		t.Fatalf("a complete stream was refused: %v", err)
	}
}

// A repository the host prepared in the workspace image is used as is, and
// its marker becomes the state the export starts from, once.
func TestCheckoutAdoptsAPreparedRepository(t *testing.T) {
	base := t.TempDir()
	repo := filepath.Join(base, "acme", "app")
	if err := os.MkdirAll(filepath.Join(repo, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	head := strings.Repeat("ab", 20)
	lfs := strings.Repeat("cd", 32)
	marker := filepath.Join(repo, checkoutPreparedFile)
	if err := os.WriteFile(marker, []byte(`{"base":"`+head+`","lfs":["`+lfs+`"]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv(checkoutPathEnv, repo)
	t.Setenv(checkoutCommitEnv, strings.Repeat("01", 20))
	t.Setenv(checkoutVsockEnv, "5002")
	c, err := checkoutFromEnv(base, nil)
	if err != nil {
		t.Fatal(err)
	}
	c.dial = func(uint32) (net.Conn, error) { t.Fatal("a prepared repository was seeded again"); return nil, nil }

	result, err := c.seed(context.Background())
	if err != nil || result != "prepared" {
		t.Fatalf("seed = %q, %v", result, err)
	}
	state, err := os.ReadFile(c.state)
	if err != nil || !strings.Contains(string(state), head) || !strings.Contains(string(state), lfs) {
		t.Fatalf("state %q, %v", state, err)
	}
	if _, err := os.Lstat(marker); err == nil {
		t.Fatal("the marker stayed in the repository")
	}
	if result, _ := c.seed(context.Background()); result != "present" {
		t.Fatalf("a second worker found %q", result)
	}
}
