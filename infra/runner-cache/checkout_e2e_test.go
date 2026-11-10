//go:build darwin || linux

package cachevolumes

import (
	"context"
	"crypto/sha256"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Builds a real checkout master from what a guest exports after an anonymous,
// depth-1 clone of a public repository with Git LFS, then mounts a clone of it
// the way a guest does and runs what actions/checkout runs, with real images,
// git and git-lfs. Opt in with TUIST_CHECKOUT_E2E=1. On Linux it runs as root,
// with TUIST_CHECKOUT_E2E_ROOT on a reflink filesystem.
func TestCheckoutMasterEndToEnd(t *testing.T) {
	if os.Getenv("TUIST_CHECKOUT_E2E") == "" {
		t.Skip("set TUIST_CHECKOUT_E2E=1 to build a real checkout master")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	c := e2eCheckouts(t)
	if err := c.Prepare(ctx); err != nil {
		t.Fatal(err)
	}
	url := e2eRepository
	env := e2eGuestEnv(c)
	gitIn := e2eGit(t, env)

	// What a guest's actions/checkout leaves on its own disk, and what it exports.
	guest := filepath.Join(t.TempDir(), "guest")
	gitIn(filepath.Dir(guest), "clone", "-q", "--depth", "1", url, guest)
	gitIn(guest, "lfs", "fetch", "origin", "HEAD")
	head := strings.TrimSpace(gitIn(guest, "rev-parse", "HEAD"))
	task := checkoutTestTask()
	task.CloneURL, task.Commit, task.Export, task.UID = url, head, c.Incoming("job"), e2eUID
	exportFromGuest(t, guest, task.Export, env, "")

	if err := c.build(ctx, task, true, nil, 0); err != nil {
		t.Fatal(err)
	}
	workspace := mountBranch(t, c)
	git := func(args ...string) string { return gitIn(workspace, args...) }
	assertOwnedByJob(t, workspace)
	if origin := strings.TrimSpace(git("config", "remote.origin.url")); origin != url {
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
	// What actions/checkout runs next: its depth-1 fetch, then the LFS fetch of the
	// commit, which finds every object here and asks GitHub for nothing.
	git("-c", "protocol.version=2", "fetch", "--no-tags", "--prune", "--depth=1", "origin", "+"+head+":refs/remotes/origin/main")
	git("lfs", "install", "--local")
	trace := exec.Command("git", "lfs", "fetch", "origin", "refs/remotes/origin/main")
	trace.Dir, trace.Env = workspace, append(env, "GIT_TRACE=1", "GIT_CURL_VERBOSE=0")
	if out, err := trace.CombinedOutput(); err != nil || strings.Contains(string(out), "objects/batch") {
		t.Fatalf("LFS fetch went to GitHub: %v\n%s", err, out)
	}
	if refs := git("for-each-ref", "--format=%(refname)", "refs/heads/"); refs != "" {
		t.Fatalf("branches must stay remote-tracking, got local %q", refs)
	}

	// A later job on the mounted master exports only what it added.
	writeTestFile(t, filepath.Join(workspace, "job.txt"), "added by a job")
	git("add", "job.txt")
	command := exec.Command("git", "commit", "-q", "-m", "job")
	command.Dir, command.Env = workspace, append(env, "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
	if out, err := command.CombinedOutput(); err != nil {
		t.Fatalf("%v %s", err, out)
	}
	job := strings.TrimSpace(git("rev-parse", "HEAD"))
	next := checkoutTestTask()
	next.CloneURL, next.Commit, next.DefaultBranchJob, next.Export, next.UID = url, job, false, c.Incoming("next"), e2eUID
	exportFromGuest(t, workspace, next.Export, env, head)
	if info, _ := os.Stat(filepath.Join(next.Export, "pack")); info.Size() > 4096 {
		t.Fatalf("a delta export carried %d bytes", info.Size())
	}
	unmountBranch(workspace)
	meta, err := c.readMeta(checkoutTestScope, 1)
	if err != nil {
		t.Fatal(err)
	}
	if err := c.build(ctx, next, false, meta, 0); err != nil {
		t.Fatal(err)
	}
	workspace = mountBranch(t, c)
	catFile := exec.Command("git", "-C", workspace, "cat-file", "-e", job+"^{commit}")
	catFile.Env = env
	if out, err := catFile.CombinedOutput(); err != nil {
		t.Fatalf("the job's commit did not reach the master: %s", out)
	}
	if tip := strings.TrimSpace(gitIn(workspace, "rev-parse", "HEAD")); tip != head {
		t.Fatalf("a branch job moved the tip to %s", tip)
	}
}

// Starts a real checkout master from a branch job's export while the lineage has
// no HEAD, then moves its tip with the first default-branch job's export.
func TestCheckoutBranchMasterEndToEnd(t *testing.T) {
	if os.Getenv("TUIST_CHECKOUT_E2E") == "" {
		t.Skip("set TUIST_CHECKOUT_E2E=1 to build a real checkout master")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	c := e2eCheckouts(t)
	if err := c.Prepare(ctx); err != nil {
		t.Fatal(err)
	}
	env := e2eGuestEnv(c)
	gitIn := e2eGit(t, env)
	guest := filepath.Join(t.TempDir(), "guest")
	gitIn(filepath.Dir(guest), "clone", "-q", "--depth", "1", e2eRepository, guest)
	gitIn(guest, "lfs", "fetch", "origin", "HEAD")
	head := strings.TrimSpace(gitIn(guest, "rev-parse", "HEAD"))
	branch := checkoutTestTask()
	branch.CloneURL, branch.Commit, branch.Export, branch.UID = e2eRepository, head, c.Incoming("branch"), e2eUID
	branch.DefaultBranchJob, branch.MayStartMaster = false, true
	exportFromGuest(t, guest, branch.Export, env, "")

	if err := c.build(ctx, branch, true, nil, 0); err != nil {
		t.Fatal(err)
	}
	workspace := mountBranch(t, c)
	git := func(args ...string) string { return gitIn(workspace, args...) }
	if tip := strings.TrimSpace(git("rev-parse", "HEAD")); tip != head {
		t.Fatalf("tip %s, want the branch job's commit %s", tip, head)
	}
	if status := git("status", "--porcelain"); status != "" {
		t.Fatalf("the mounted checkout is not clean:\n%s", status)
	}
	image, err := os.ReadFile(filepath.Join(workspace, "public", "chia-seeds.jpg"))
	if err != nil || len(image) < 1024 || strings.HasPrefix(string(image), "version https://git-lfs") {
		t.Fatal("LFS content was not smudged into the working tree")
	}
	if refs := git("for-each-ref", "--format=%(refname)", "refs/remotes/"); refs != "" {
		t.Fatalf("a branch job set remote-tracking refs %q", refs)
	}

	writeTestFile(t, filepath.Join(workspace, "main.txt"), "on the default branch")
	git("add", "main.txt")
	command := exec.Command("git", "commit", "-q", "-m", "main")
	command.Dir, command.Env = workspace, append(env, "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
	if out, err := command.CombinedOutput(); err != nil {
		t.Fatalf("%v %s", err, out)
	}
	commit := strings.TrimSpace(git("rev-parse", "HEAD"))
	main := checkoutTestTask()
	main.CloneURL, main.Commit, main.Export, main.UID = e2eRepository, commit, c.Incoming("main"), e2eUID
	main.BaseGeneration, main.ImageDigest, main.ContentDigest = 1, strings.Repeat("b", 40), strings.Repeat("c", 64)
	exportFromGuest(t, workspace, main.Export, env, head)
	unmountBranch(workspace)
	meta, err := c.readMeta(checkoutTestScope, 1)
	if err != nil {
		t.Fatal(err)
	}
	if err := c.build(ctx, main, false, meta, 0); err != nil {
		t.Fatal(err)
	}
	workspace = mountBranch(t, c)
	if tip := strings.TrimSpace(gitIn(workspace, "rev-parse", "HEAD")); tip != commit {
		t.Fatalf("a default-branch job left the tip at %s", tip)
	}
	if ref := strings.TrimSpace(gitIn(workspace, "rev-parse", "refs/remotes/origin/main")); ref != commit {
		t.Fatalf("origin/main %s", ref)
	}
	if status := gitIn(workspace, "status", "--porcelain"); status != "" {
		t.Fatalf("the moved checkout is not clean:\n%s", status)
	}
}

// Starts a real checkout master from a pull request job's export: actions/checkout
// fetches GitHub's test merge of the pull request at depth 1, so the exported
// commit is a merge whose parents, the job's commit among them, are not exported.
func TestCheckoutPullRequestMergeMasterEndToEnd(t *testing.T) {
	if os.Getenv("TUIST_CHECKOUT_E2E") == "" {
		t.Skip("set TUIST_CHECKOUT_E2E=1 to build a real checkout master")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	c := e2eCheckouts(t)
	if err := c.Prepare(ctx); err != nil {
		t.Fatal(err)
	}
	env := e2eGuestEnv(c)
	gitIn := e2eGit(t, env)
	commitAs := e2eGit(t, append(append([]string(nil), env...), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t"))

	// The repository, a pull request's commit on it, and GitHub's test merge of it.
	origin := filepath.Join(t.TempDir(), "origin")
	gitIn(filepath.Dir(origin), "clone", "-q", "--depth", "1", e2eRepository, origin)
	gitIn(origin, "lfs", "fetch", "origin", "HEAD")
	base := strings.TrimSpace(gitIn(origin, "rev-parse", "HEAD"))
	writeTestFile(t, filepath.Join(origin, "pull-request.txt"), "added by a pull request")
	gitIn(origin, "add", "pull-request.txt")
	commitAs(origin, "commit", "-q", "-m", "pull request")
	head := strings.TrimSpace(gitIn(origin, "rev-parse", "HEAD"))
	tree := strings.TrimSpace(gitIn(origin, "rev-parse", "HEAD^{tree}"))
	merge := strings.TrimSpace(commitAs(origin, "commit-tree", tree, "-p", base, "-p", head, "-m", "Merge "+head+" into "+base))
	gitIn(origin, "update-ref", "refs/pull/1/merge", merge)

	// What actions/checkout runs for a pull_request event, LFS objects included.
	guest := filepath.Join(t.TempDir(), "guest")
	gitIn(filepath.Dir(guest), "init", "-q", guest)
	gitIn(guest, "fetch", "-q", "--no-tags", "--depth=1", "file://"+origin, "+refs/pull/1/merge:refs/remotes/pull/1/merge")
	if out, err := exec.Command("cp", "-R", filepath.Join(origin, ".git", "lfs"), filepath.Join(guest, ".git", "lfs")).CombinedOutput(); err != nil {
		t.Fatalf("%v %s", err, out)
	}
	gitIn(guest, "checkout", "-q", "--detach", merge)
	if shallow, _ := os.ReadFile(filepath.Join(guest, ".git", "shallow")); strings.TrimSpace(string(shallow)) != merge {
		t.Fatalf("the guest's checkout is not a depth-1 fetch of the merge: %q", shallow)
	}
	task := checkoutTestTask()
	task.CloneURL, task.Commit, task.Export, task.UID = e2eRepository, head, c.Incoming("pull-request"), e2eUID
	task.DefaultBranchJob, task.MayStartMaster = false, true
	exportFromGuest(t, guest, task.Export, env, "")

	if err := c.build(ctx, task, true, nil, 0); err != nil {
		t.Fatal(err)
	}
	workspace := mountBranch(t, c)
	if tip := strings.TrimSpace(gitIn(workspace, "rev-parse", "HEAD")); tip != merge {
		t.Fatalf("tip %s, want the job's test merge %s", tip, merge)
	}
	if status := gitIn(workspace, "status", "--porcelain"); status != "" {
		t.Fatalf("the mounted checkout is not clean:\n%s", status)
	}
	if data, err := os.ReadFile(filepath.Join(workspace, "pull-request.txt")); err != nil || string(data) != "added by a pull request" {
		t.Fatal("the merge's tree is not checked out")
	}
	image, err := os.ReadFile(filepath.Join(workspace, "public", "chia-seeds.jpg"))
	if err != nil || len(image) < 1024 || strings.HasPrefix(string(image), "version https://git-lfs") {
		t.Fatal("LFS content was not smudged into the working tree")
	}
}

const e2eRepository = "https://github.com/jimthoburn/github-lfs-example"

// e2eGuestEnv is a guest's git: git-lfs configured, but none of the host's hook isolation.
func e2eGuestEnv(c *Checkouts) []string {
	env := append(c.gitEnv(), "GIT_LFS_SKIP_SMUDGE=0")
	for i, variable := range env {
		if variable == "GIT_CONFIG_VALUE_0=/dev/null" {
			env[i] = "GIT_CONFIG_VALUE_0="
		}
	}
	return env
}

func e2eGit(t *testing.T, env []string) func(dir string, args ...string) string {
	return func(dir string, args ...string) string {
		t.Helper()
		command := exec.Command("git", args...)
		command.Dir, command.Env = dir, env
		out, err := command.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v %s", args, err, out)
		}
		return string(out)
	}
}

// exportFromGuest does what the guest's teardown does: pack what HEAD adds over
// base and copy the LFS objects.
func exportFromGuest(t *testing.T, repo, dst string, env []string, base string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(dst, "lfs"), 0755); err != nil {
		t.Fatal(err)
	}
	pack, err := os.Create(filepath.Join(dst, "pack"))
	if err != nil {
		t.Fatal(err)
	}
	revisions := "HEAD\n"
	if base != "" {
		revisions += "--not\n" + base + "\n"
	}
	command := exec.Command("git", "pack-objects", "--revs", "--stdout", "-q")
	command.Dir, command.Env, command.Stdin, command.Stdout = repo, env, strings.NewReader(revisions), pack
	if err := command.Run(); err != nil {
		t.Fatal(err)
	}
	pack.Close()
	revParse := exec.Command("git", "-C", repo, "rev-parse", "HEAD")
	revParse.Env = env
	head, _ := revParse.Output()
	writeTestFile(t, filepath.Join(dst, "head"), string(head))
	if shallow, err := os.ReadFile(filepath.Join(repo, ".git", "shallow")); err == nil {
		writeTestFile(t, filepath.Join(dst, "shallow"), string(shallow))
	}
	if base != "" {
		return
	}
	objects := filepath.Join(repo, ".git", "lfs", "objects")
	_ = filepath.WalkDir(objects, func(path string, entry os.DirEntry, err error) error {
		if err != nil || !entry.Type().IsRegular() || !checkoutOID.MatchString(entry.Name()) {
			return nil
		}
		in, _ := os.Open(path)
		defer in.Close()
		out, _ := os.Create(filepath.Join(dst, "lfs", entry.Name()))
		defer out.Close()
		_, _ = io.Copy(out, in)
		return nil
	})
}

func writeTestFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

// e2eUID owns the working tree on Linux, as the runner user does in guests.
var e2eUID = map[bool]int{true: 1000, false: 0}[runtime.GOOS == "linux"]

func e2eCheckouts(t *testing.T) *Checkouts {
	t.Helper()
	path := "/usr/bin:/bin"
	if lfs, err := exec.LookPath("git-lfs"); err == nil {
		path = filepath.Dir(lfs) + ":" + path
	}
	if runtime.GOOS == "darwin" {
		return &Checkouts{Root: t.TempDir(), Images: &APFSCheckoutImages{}, Path: path}
	}
	root := os.Getenv("TUIST_CHECKOUT_E2E_ROOT")
	if root == "" || os.Geteuid() != 0 {
		t.Skip("set TUIST_CHECKOUT_E2E_ROOT to a directory on a reflink filesystem and run as root")
	}
	root, err := os.MkdirTemp(root, "checkouts-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(root) })
	return &Checkouts{Root: root, Images: &Ext4CheckoutImages{}, Path: path}
}

type mountedBranch struct{ image, mount string }

var mountedBranches = map[string]mountedBranch{}

// mountBranch mounts a clone of the master the way a job gets it: attached by
// the guest on macOS, loop-mounted by the host on Linux.
func mountBranch(t *testing.T, c *Checkouts) string {
	t.Helper()
	dir, err := os.MkdirTemp(c.Root, "branch-")
	if err != nil {
		t.Fatal(err)
	}
	branch := filepath.Join(dir, "branch"+filepath.Ext(c.Images.MasterName()))
	if err := c.Images.Clone(context.Background(), c.Master(checkoutTestScope, 1), branch); err != nil {
		t.Fatal(err)
	}
	mount := filepath.Join(dir, "mnt")
	if err := os.MkdirAll(mount, 0755); err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS == "darwin" {
		if out, err := exec.Command("hdiutil", "attach", branch, "-owners", "off", "-nobrowse", "-quiet", "-mountpoint", mount).CombinedOutput(); err != nil {
			t.Fatal(string(out))
		}
	} else if err := c.Images.Attach(context.Background(), branch, mount, false); err != nil {
		t.Fatal(err)
	}
	workspace := c.Images.Repository(mount)
	mountedBranches[workspace] = mountedBranch{image: branch, mount: mount}
	t.Cleanup(func() { unmountBranch(workspace) })
	return workspace
}

func unmountBranch(workspace string) {
	branch, ok := mountedBranches[workspace]
	if !ok {
		return
	}
	delete(mountedBranches, workspace)
	if runtime.GOOS == "darwin" {
		_ = exec.Command("hdiutil", "detach", branch.mount, "-force", "-quiet").Run()
		return
	}
	(&Ext4CheckoutImages{}).Abandon(context.Background(), branch.image, branch.mount)
}

// assertOwnedByJob checks the tree belongs to the job's user, who writes to it.
func assertOwnedByJob(t *testing.T, workspace string) {
	t.Helper()
	if runtime.GOOS != "linux" {
		return
	}
	out, err := exec.Command("find", workspace, "!", "-uid", strconv.Itoa(e2eUID), "-print", "-quit").CombinedOutput()
	if err != nil || len(strings.TrimSpace(string(out))) > 0 {
		t.Fatalf("not owned by the job's user: %s %v", out, err)
	}
}
