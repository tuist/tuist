//go:build darwin

package podagent

import (
	"context"
	"crypto/sha256"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Builds a real checkout master from a public repository with Git LFS and
// mounts a clone of it the way a guest does, with real hdiutil, git and the
// pinned git-lfs. Opt in with TUIST_CHECKOUT_E2E_TOKEN set to a GitHub token.
func TestCheckoutMasterEndToEnd(t *testing.T) {
	token := os.Getenv("TUIST_CHECKOUT_E2E_TOKEN")
	if token == "" {
		t.Skip("set TUIST_CHECKOUT_E2E_TOKEN to build a real checkout master")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	c := &Checkouts{Root: t.TempDir()}
	if err := c.probe(ctx); err != nil {
		t.Fatal(err)
	}
	task := checkoutTask{Scope: checkoutTestScope, Generation: 1, CloneURL: "https://github.com/jimthoburn/github-lfs-example", DefaultBranch: "main", Token: token, TokenExpiresAt: time.Now().Add(time.Hour)}
	if err := c.build(ctx, task, true, nil, 0); err != nil {
		t.Fatal(err)
	}
	branch := filepath.Join(t.TempDir(), "branch.sparseimage")
	if out, err := exec.Command("cp", "-c", c.Master(checkoutTestScope, 1), branch).CombinedOutput(); err != nil {
		t.Fatal(string(out))
	}
	workspace := filepath.Join(t.TempDir(), "repo")
	if err := os.MkdirAll(workspace, 0755); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command("hdiutil", "attach", branch, "-owners", "off", "-nobrowse", "-quiet", "-mountpoint", workspace).CombinedOutput(); err != nil {
		t.Fatal(string(out))
	}
	defer exec.Command("hdiutil", "detach", workspace, "-force", "-quiet").Run()
	env := append(c.baseEnv(), "GIT_LFS_SKIP_SMUDGE=0")
	git := func(args ...string) string {
		command := exec.Command("git", args...)
		command.Dir, command.Env = workspace, env
		out, err := command.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v %s", args, err, out)
		}
		return string(out)
	}
	if origin := strings.TrimSpace(git("config", "remote.origin.url")); origin != task.CloneURL {
		t.Fatalf("origin %q", origin)
	}
	if status := git("status", "--porcelain"); status != "" {
		t.Fatalf("the mounted checkout is not clean:\n%s", status)
	}
	image, err := os.ReadFile(filepath.Join(workspace, "public", "chia-seeds.jpg"))
	if err != nil || len(image) < 1024 || strings.HasPrefix(string(image), "version https://git-lfs") {
		t.Fatal("LFS content was not smudged into the working tree")
	}
	// actions/checkout runs clean and reset before it configures the LFS filter.
	files := []string{"public/chia-seeds.jpg", "public/chia-seeds.webp", "README.md"}
	before := map[string]time.Time{}
	for _, file := range files {
		info, err := os.Stat(filepath.Join(workspace, file))
		if err != nil {
			t.Fatal(err)
		}
		before[file] = info.ModTime()
	}
	git("clean", "-ffdx")
	git("reset", "--hard", "HEAD")
	for _, file := range files {
		info, _ := os.Stat(filepath.Join(workspace, file))
		if !info.ModTime().Equal(before[file]) {
			t.Fatalf("clean and reset rewrote %s", file)
		}
	}
	image, _ = os.ReadFile(filepath.Join(workspace, "public", "chia-seeds.jpg"))
	if sha256.Sum256(image) == sha256.Sum256(nil) || strings.HasPrefix(string(image), "version https://git-lfs") {
		t.Fatal("clean and reset turned LFS content back into a pointer")
	}
	// What actions/checkout runs next: with every object present, LFS asks GitHub for nothing.
	git("lfs", "install", "--local")
	trace := exec.Command("git", "lfs", "fetch", "origin", "refs/remotes/origin/main")
	trace.Dir, trace.Env = workspace, append(env, "GIT_TRACE=1", "GIT_CURL_VERBOSE=0")
	if out, err := trace.CombinedOutput(); err != nil || strings.Contains(string(out), "objects/batch") {
		t.Fatalf("LFS fetch went to GitHub: %v\n%s", err, out)
	}
	if refs := git("for-each-ref", "--format=%(refname)", "refs/heads/"); refs != "" {
		t.Fatalf("branches must stay remote-tracking, got local %q", refs)
	}
}
