//go:build darwin || linux

package cachevolumes

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// treeCheckoutImages keeps each image's tree in a directory the image file names,
// so builds run real git on any host. Like umount, Detach refuses while a process
// still works in the mounted tree.
type treeCheckoutImages struct{}

func (treeCheckoutImages) MasterName() string { return "master.img" }

func (treeCheckoutImages) Create(_ context.Context, path string, _ int64) error {
	tree, err := os.MkdirTemp(filepath.Dir(path), "tree-")
	if err != nil {
		return err
	}
	return os.WriteFile(path, []byte(tree), 0600)
}

func (treeCheckoutImages) Clone(_ context.Context, src, dst string) error {
	from, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	tree, err := os.MkdirTemp(filepath.Dir(dst), "tree-")
	if err != nil {
		return err
	}
	if out, err := exec.Command("cp", "-R", string(from)+"/.", tree).CombinedOutput(); err != nil {
		return fmt.Errorf("cp: %w (%s)", err, out)
	}
	return os.WriteFile(dst, []byte(tree), 0600)
}

func (treeCheckoutImages) Attach(_ context.Context, image, mount string, _ bool) error {
	tree, err := os.ReadFile(image)
	if err != nil {
		return err
	}
	if err := os.Remove(mount); err != nil {
		return err
	}
	return os.Rename(string(tree), mount)
}

func (treeCheckoutImages) Detach(_ context.Context, image, mount string) error {
	if pids := processesIn(mount); len(pids) > 0 {
		return fmt.Errorf("umount: %s: target is busy (pids %s)", mount, strings.Join(pids, " "))
	}
	tree, err := os.ReadFile(image)
	if err != nil {
		return err
	}
	if err := os.Rename(mount, string(tree)); err != nil {
		return err
	}
	return os.Mkdir(mount, 0700)
}

func (treeCheckoutImages) Abandon(_ context.Context, image, mount string) {
	tree, err := os.ReadFile(image)
	if err != nil {
		return
	}
	if _, err := os.Stat(string(tree)); os.IsNotExist(err) {
		_ = os.Rename(mount, string(tree))
	}
}

func (treeCheckoutImages) Repository(mount string) string { return mount }

func (treeCheckoutImages) Own(context.Context, string, int) error { return nil }

// processesIn lists the processes whose working directory is in dir.
func processesIn(dir string) []string {
	if resolved, err := filepath.EvalSymlinks(dir); err == nil {
		dir = resolved
	}
	inside := func(path string) bool { return path == dir || strings.HasPrefix(path, dir+"/") }
	var pids []string
	if runtime.GOOS == "linux" {
		links, _ := filepath.Glob("/proc/[0-9]*/cwd")
		for _, link := range links {
			if cwd, err := os.Readlink(link); err == nil && inside(cwd) {
				pids = append(pids, filepath.Base(filepath.Dir(link)))
			}
		}
		return pids
	}
	out, _ := exec.Command("lsof", "-a", "-d", "cwd", "-F", "pn").Output()
	pid := ""
	for _, line := range strings.Split(string(out), "\n") {
		switch {
		case strings.HasPrefix(line, "p"):
			pid = line[1:]
		case strings.HasPrefix(line, "n") && inside(line[1:]):
			pids = append(pids, pid)
		}
	}
	return pids
}

// Every ingest adds the export's pack to the master, so after enough jobs git's
// automatic gc repacks it. git runs that repack in the background by default; it
// kept the image mounted, every later build failed to unmount it (`umount: target
// is busy`) and the master never advanced again.
func TestCheckoutBuildRepacksBeforeUnmounting(t *testing.T) {
	lfs, err := exec.LookPath("git-lfs")
	if err != nil {
		t.Skip("git-lfs is not installed")
	}
	gitPath, err := exec.LookPath("git")
	if err != nil {
		t.Skip("git is not installed")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	c := &Checkouts{Root: t.TempDir(), Images: treeCheckoutImages{}, Path: filepath.Dir(lfs) + ":" + filepath.Dir(gitPath) + ":/usr/bin:/bin"}
	// A second pack is one too many, so the second build's ingest starts the repack
	// that production masters start after 50 jobs.
	c.Run = func(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error) {
		return runCheckoutCommand(ctx, dir, append(env, "GIT_CONFIG_PARAMETERS='gc.autopacklimit'='1'"), name, args...)
	}
	env := e2eGuestEnv(c)
	git := e2eGit(t, env)
	guest := filepath.Join(t.TempDir(), "guest")
	git(filepath.Dir(guest), "init", "-q", guest)
	commit := func(file string) string {
		writeTestFile(t, filepath.Join(guest, file), file)
		git(guest, "add", file)
		git(guest, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", file)
		return strings.TrimSpace(git(guest, "rev-parse", "HEAD"))
	}

	head := commit("first.txt")
	task := checkoutTestTask()
	task.Commit, task.Export = head, c.Incoming("first")
	exportFromGuest(t, guest, task.Export, env, "")
	if err := c.build(ctx, task, true, nil, 0); err != nil {
		t.Fatal(err)
	}

	next := checkoutTestTask()
	next.Commit, next.Export = commit("second.txt"), c.Incoming("second")
	exportFromGuest(t, guest, next.Export, env, head)
	meta, err := c.readMeta(checkoutTestScope, 1)
	if err != nil {
		t.Fatal(err)
	}
	if err := c.build(ctx, next, false, meta, 0); err != nil {
		t.Fatalf("the master did not advance: %v", err)
	}
	if pids := processesIn(c.Root); len(pids) > 0 {
		t.Fatalf("the build left processes running in the master: %v", pids)
	}
	if meta, err := c.readMeta(checkoutTestScope, 1); err != nil || meta.Tip != next.Commit {
		t.Fatalf("meta %+v %v", meta, err)
	}
	tree, err := os.ReadFile(c.Master(checkoutTestScope, 1))
	if err != nil {
		t.Fatal(err)
	}
	if packs, _ := filepath.Glob(filepath.Join(string(tree), ".git", "objects", "pack", "*.pack")); len(packs) != 1 {
		t.Fatalf("the installed master was not repacked: %v", packs)
	}
}
