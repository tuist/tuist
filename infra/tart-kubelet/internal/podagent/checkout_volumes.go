package podagent

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

const (
	checkoutCapacity     = 60_000_000_000
	checkoutBuildRoom    = 20_000_000_000
	checkoutRefreshRoom  = 10_000_000_000
	checkoutRefreshEvery = 2 * time.Minute
	checkoutRebuildAfter = 30 * 24 * time.Hour
	checkoutRecentFor    = 14 * 24 * time.Hour
	checkoutIdleFor      = 7 * 24 * time.Hour
	checkoutQueue        = 16

	// The git-lfs the populator runs, pinned and verified before it is used.
	gitLFSURL    = "https://github.com/git-lfs/git-lfs/releases/download/v3.8.0/git-lfs-darwin-arm64-v3.8.0.zip"
	gitLFSSHA256 = "caff76a7d070d8160c89bc39b6e85d98f24135b6fed038a3b4de2590d25102d8"
	gitLFSEntry  = "git-lfs-3.8.0/git-lfs"
)

var checkoutScope = regexp.MustCompile(`^[a-f0-9]{64}$`)
var checkoutRepository = regexp.MustCompile(`^https://github\.com/[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$`)
var checkoutCommit = regexp.MustCompile(`^[a-f0-9]{40}$`)
var checkoutBranch = regexp.MustCompile(`^[A-Za-z0-9._/-]{1,255}$`)

// Checkouts keeps the host-written masters of checkout volumes: a repository's
// working tree at its default-branch tip plus its full .git and LFS objects.
// Only this type writes them, from GitHub, with a token that can only read the
// repository. Guests get CoW clones that are never published.
type Checkouts struct {
	Root string
	Run  func(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error)
	// Room reserves disk for a build until the returned release is called.
	Room func(context.Context, uint64) (func(), error)
	Now  func() time.Time
	// Download fetches the pinned git-lfs release archive.
	Download func(context.Context) ([]byte, error)

	mu      sync.Mutex
	locks   map[string]*sync.Mutex
	pending map[string]checkoutTask
	// waiting holds builds refused for disk room until a reconcile retries them.
	waiting map[string]checkoutTask
	busy    map[string]bool
	queue   chan string
	ready   bool
}

type checkoutTask struct {
	Scope          string
	Generation     int64
	CloneURL       string
	DefaultBranch  string
	Commit         string
	Token          string
	TokenExpiresAt time.Time
}

type checkoutMeta struct {
	Tip         string               `json:"tip"`
	BuiltAt     time.Time            `json:"built_at"`
	RefreshedAt time.Time            `json:"refreshed_at"`
	Recent      map[string]time.Time `json:"recent"`
}

func (c *Checkouts) now() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

func (c *Checkouts) run(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error) {
	if c.Run != nil {
		return c.Run(ctx, dir, env, name, args...)
	}
	command := exec.CommandContext(ctx, name, args...)
	command.Dir = dir
	command.Env = env
	out, err := command.CombinedOutput()
	if err != nil {
		// Never include argv or env: neither may carry credentials, but keep the
		// error bounded to what the command printed.
		return out, fmt.Errorf("%s: %w (%s)", name, err, strings.TrimSpace(string(out)))
	}
	return out, nil
}

func (c *Checkouts) lock(scope string) *sync.Mutex {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.locks == nil {
		c.locks = map[string]*sync.Mutex{}
	}
	lock := c.locks[scope]
	if lock == nil {
		lock = &sync.Mutex{}
		c.locks[scope] = lock
	}
	return lock
}

func (c *Checkouts) dir(scope string, generation int64) string {
	return filepath.Join(c.Root, scope, strconv.FormatInt(generation, 10))
}

func (c *Checkouts) masterPath(scope string, generation int64) string {
	return filepath.Join(c.dir(scope, generation), "master.sparseimage")
}

// Master returns the host-built master for a checkout volume's clear generation,
// or "" when this host has none yet.
func (c *Checkouts) Master(scope string, generation int64) string {
	if c == nil || !checkoutScope.MatchString(scope) || generation < 0 {
		return ""
	}
	path := c.masterPath(scope, generation)
	if info, err := os.Stat(path); err != nil || !info.Mode().IsRegular() {
		return ""
	}
	return path
}

// Seed clones the master into a guest's private branch under the scope lock,
// so a refresh's rename or an eviction never races the clone.
func (c *Checkouts) Seed(ctx context.Context, slot cachevolumes.Slot, dst string) error {
	if slot.Kind != cachevolumes.KindCheckout {
		return errors.New("not a checkout")
	}
	lock := c.lock(slot.Scope)
	lock.Lock()
	defer lock.Unlock()
	master := c.Master(slot.Scope, slot.Generation)
	if master == "" {
		return errors.New("checkout master unavailable")
	}
	if _, err := c.run(ctx, "", nil, "cp", "-c", master, dst); err != nil {
		return err
	}
	now := c.now()
	return os.Chtimes(master, now, now)
}

// Start runs the single build worker until ctx ends. Builds stay off when the
// host has no working git or git-lfs; jobs then check out as they do today.
func (c *Checkouts) Start(ctx context.Context) {
	c.mu.Lock()
	if c.queue == nil {
		c.queue = make(chan string, checkoutQueue)
	}
	queue := c.queue
	c.mu.Unlock()
	for {
		err := c.probe(ctx)
		if err == nil {
			break
		}
		log.FromContext(ctx).Error(err, "cached checkouts unavailable on this host; retrying")
		select {
		case <-ctx.Done():
			return
		case <-time.After(10 * time.Minute):
		}
	}
	c.mu.Lock()
	c.ready = true
	c.mu.Unlock()
	defer func() {
		c.mu.Lock()
		c.ready = false
		c.mu.Unlock()
	}()
	for {
		select {
		case <-ctx.Done():
			return
		case scope := <-queue:
			c.mu.Lock()
			task, ok := c.pending[scope]
			delete(c.pending, scope)
			c.mu.Unlock()
			if ok {
				c.process(ctx, task)
			}
		}
	}
}

func (c *Checkouts) probe(ctx context.Context) error {
	if err := os.MkdirAll(filepath.Join(c.Root, ".home"), 0700); err != nil {
		return err
	}
	if err := c.ensureGitLFS(ctx); err != nil {
		return err
	}
	for _, tool := range [][]string{{"git", "--version"}, {"git", "lfs", "version"}} {
		if _, err := c.run(ctx, c.Root, c.baseEnv(), tool[0], tool[1:]...); err != nil {
			return err
		}
	}
	return nil
}

// Enqueue asks for a refresh, or a first build, of a checkout volume. The newest
// request per volume wins; a full queue drops the request, it never blocks.
func (c *Checkouts) Enqueue(task checkoutTask) bool {
	if c == nil || !validCheckoutTask(task) {
		return false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.ready || c.queue == nil {
		return false
	}
	if c.pending == nil {
		c.pending = map[string]checkoutTask{}
	}
	delete(c.waiting, task.Scope)
	_, queued := c.pending[task.Scope]
	c.pending[task.Scope] = task
	if queued {
		return true
	}
	select {
	case c.queue <- task.Scope:
		return true
	default:
		delete(c.pending, task.Scope)
		return false
	}
}

func validCheckoutTask(task checkoutTask) bool {
	branch := task.DefaultBranch
	return checkoutScope.MatchString(task.Scope) && task.Generation >= 0 && checkoutRepository.MatchString(task.CloneURL) &&
		checkoutBranch.MatchString(branch) && !strings.Contains(branch, "..") && !strings.HasPrefix(branch, "-") &&
		!strings.HasPrefix(branch, "/") && !strings.HasSuffix(branch, "/") &&
		(task.Commit == "" || checkoutCommit.MatchString(task.Commit)) && task.Token != "" && !strings.ContainsAny(task.Token, "\r\n")
}

func (c *Checkouts) process(ctx context.Context, task checkoutTask) {
	if c.now().Add(2 * time.Minute).After(task.TokenExpiresAt) {
		return
	}
	c.dropOtherGenerations(task.Scope, task.Generation)
	meta, _ := c.readMeta(task.Scope, task.Generation)
	cold := c.Master(task.Scope, task.Generation) == "" || meta == nil || c.now().Sub(meta.BuiltAt) > checkoutRebuildAfter
	if !cold && c.now().Sub(meta.RefreshedAt) < checkoutRefreshEvery && (task.Commit == "" || !meta.Recent[task.Commit].IsZero()) {
		return
	}
	// Images are sparse: a build reserves what it is expected to write, not the cap.
	operation, budget, room := "checkout_refresh", 15*time.Minute, uint64(checkoutRefreshRoom)
	if cold {
		operation, budget, room = "checkout_build", 45*time.Minute, uint64(checkoutBuildRoom)
	}
	ctx, cancel := context.WithTimeout(ctx, budget)
	defer cancel()
	done := cachevolumes.Observer(observeCustomCache).Start(operation, "remote")
	err := c.build(ctx, task, cold, meta, room)
	done(err)
	if errors.Is(err, cachevolumes.ErrCapacity) {
		// The requesting job usually holds the room; every reconcile retries until the token expires.
		c.mu.Lock()
		if c.waiting == nil {
			c.waiting = map[string]checkoutTask{}
		}
		if _, queued := c.pending[task.Scope]; !queued {
			c.waiting[task.Scope] = task
		}
		c.mu.Unlock()
		return
	}
	if err != nil {
		log.FromContext(ctx).Error(err, "checkout master not updated", "operation", operation)
	}
}

func (c *Checkouts) build(ctx context.Context, task checkoutTask, cold bool, meta *checkoutMeta, room uint64) (err error) {
	c.setBusy(task.Scope, true)
	defer c.setBusy(task.Scope, false)
	if c.Room != nil {
		release, err := c.Room(ctx, room)
		if err != nil {
			return err
		}
		defer release()
	}
	dir := c.dir(task.Scope, task.Generation)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	next := filepath.Join(dir, "next.sparseimage")
	mount := filepath.Join(dir, "next.mnt")
	c.detach(ctx, mount)
	_ = os.Remove(next)
	defer os.Remove(next)
	if cold || meta == nil {
		meta = &checkoutMeta{BuiltAt: c.now(), Recent: map[string]time.Time{}}
		if _, err := c.run(ctx, dir, nil, "hdiutil", "create", "-size", strconv.FormatInt(checkoutCapacity/1_000_000, 10)+"m", "-type", "SPARSE", "-fs", "APFS", "-volname", "TuistCheckout", "-quiet", next); err != nil {
			return err
		}
	} else if _, err := c.run(ctx, dir, nil, "cp", "-c", c.masterPath(task.Scope, task.Generation), next); err != nil {
		return err
	}
	if err := os.MkdirAll(mount, 0700); err != nil {
		return err
	}
	if _, err := c.run(ctx, dir, nil, "hdiutil", "attach", next, "-nobrowse", "-noautoopen", "-quiet", "-mountpoint", mount); err != nil {
		return err
	}
	attached := true
	defer func() {
		if attached {
			c.detach(context.WithoutCancel(ctx), mount)
		}
	}()
	if err := c.populate(ctx, mount, task, cold, meta); err != nil {
		return err
	}
	if err := c.detachStrict(ctx, mount); err != nil {
		return err
	}
	attached = false
	_ = os.Remove(mount)
	lock := c.lock(task.Scope)
	lock.Lock()
	defer lock.Unlock()
	if err := checkoutRename(next, c.masterPath(task.Scope, task.Generation)); err != nil {
		return err
	}
	return c.writeMeta(task.Scope, task.Generation, meta)
}

func (c *Checkouts) populate(ctx context.Context, repo string, task checkoutTask, cold bool, meta *checkoutMeta) error {
	git := func(args ...string) ([]byte, error) { return c.run(ctx, repo, c.taskEnv(task), "git", args...) }
	if cold {
		if _, err := git("init", "-q", "."); err != nil {
			return err
		}
		if _, err := git("remote", "add", "origin", task.CloneURL); err != nil {
			return err
		}
		for _, setting := range [][2]string{{"core.checkStat", "minimal"}, {"core.trustctime", "false"}} {
			if _, err := git("config", setting[0], setting[1]); err != nil {
				return err
			}
		}
		// The guest's fseventsd may recreate this directory; keep the tree clean.
		if err := os.WriteFile(filepath.Join(repo, ".git", "info", "exclude"), []byte("/.fseventsd/\n"), 0644); err != nil {
			return err
		}
	} else if _, err := git("remote", "set-url", "origin", task.CloneURL); err != nil {
		return err
	}
	// Branches stay remote-tracking: actions/checkout deletes local branches
	// before it fetches, and the refs it keeps are what it advertises as haves.
	if _, err := git("-c", "protocol.version=2", "fetch", "--prune", "--no-tags", "--quiet", "origin",
		"+refs/heads/*:refs/remotes/origin/*", "+refs/tags/*:refs/tags/*"); err != nil {
		return err
	}
	lfsRefs := []string{"refs/remotes/origin/" + task.DefaultBranch}
	if task.Commit != "" {
		recent := "refs/tuist/recent/" + task.Commit
		if _, err := git("-c", "protocol.version=2", "fetch", "--no-tags", "--quiet", "origin", "+"+task.Commit+":"+recent); err == nil {
			meta.Recent[task.Commit] = c.now()
			lfsRefs = append(lfsRefs, recent)
		}
	}
	for commit, at := range meta.Recent {
		if c.now().Sub(at) > checkoutRecentFor {
			_, _ = git("update-ref", "-d", "refs/tuist/recent/"+commit)
			delete(meta.Recent, commit)
		}
	}
	if _, err := git("checkout", "-q", "--detach", "--force", lfsRefs[0]); err != nil {
		return err
	}
	if _, err := git(append([]string{"lfs", "fetch", "origin"}, lfsRefs...)...); err != nil {
		return err
	}
	if _, err := git("lfs", "checkout"); err != nil {
		return err
	}
	// Record the stat data of smudged files in an index written after their
	// mtimes. An entry modified in the second its index was written is racily
	// clean: git rehashes it later, and in a guest that has not configured the
	// LFS filter yet (actions/checkout runs its clean and reset first) that turns
	// LFS files back into pointers.
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(time.Until(c.now().Truncate(time.Second).Add(1100 * time.Millisecond))):
	}
	if _, err := git("update-index", "-q", "--really-refresh"); err != nil {
		return err
	}
	tip, err := git("rev-parse", "HEAD")
	if err != nil {
		return err
	}
	meta.Tip = strings.TrimSpace(string(tip))
	meta.RefreshedAt = c.now()
	return nil
}

func (c *Checkouts) baseEnv() []string {
	return []string{
		"PATH=" + filepath.Join(c.Root, ".bin") + ":/usr/bin:/bin",
		"HOME=" + filepath.Join(c.Root, ".home"),
		"GIT_CONFIG_NOSYSTEM=1",
		"GIT_CONFIG_GLOBAL=/dev/null",
		"GIT_TERMINAL_PROMPT=0",
		"GIT_LFS_SKIP_SMUDGE=1",
	}
}

// The token reaches git only through environment-backed configuration for the
// duration of a command: never argv, never .git/config, never the remote URL.
func (c *Checkouts) taskEnv(task checkoutTask) []string {
	credential := base64.StdEncoding.EncodeToString([]byte("x-access-token:" + task.Token))
	settings := [][2]string{
		{"http.https://github.com/.extraheader", "AUTHORIZATION: basic " + credential},
		{"credential.helper", ""},
		{"core.hooksPath", "/dev/null"},
		{"lfs.fetchinclude", ""},
		{"lfs.fetchexclude", ""},
		{"filter.lfs.clean", "git-lfs clean -- %f"},
		{"filter.lfs.smudge", "git-lfs smudge -- %f"},
		{"filter.lfs.process", "git-lfs filter-process"},
		{"filter.lfs.required", "true"},
	}
	env := append(c.baseEnv(), "GIT_CONFIG_COUNT="+strconv.Itoa(len(settings)))
	for i, setting := range settings {
		env = append(env, fmt.Sprintf("GIT_CONFIG_KEY_%d=%s", i, setting[0]), fmt.Sprintf("GIT_CONFIG_VALUE_%d=%s", i, setting[1]))
	}
	return env
}

func (c *Checkouts) detach(ctx context.Context, mount string) {
	if _, err := os.Stat(mount); err != nil {
		return
	}
	if _, err := c.run(ctx, "", nil, "hdiutil", "detach", mount, "-quiet"); err != nil {
		_, _ = c.run(ctx, "", nil, "hdiutil", "detach", mount, "-force", "-quiet")
	}
}

func (c *Checkouts) detachStrict(ctx context.Context, mount string) error {
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		if _, err = c.run(ctx, "", nil, "hdiutil", "detach", mount, "-quiet"); err == nil {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}
	return err
}

func (c *Checkouts) readMeta(scope string, generation int64) (*checkoutMeta, error) {
	data, err := os.ReadFile(filepath.Join(c.dir(scope, generation), "master.json"))
	if err != nil {
		return nil, err
	}
	var meta checkoutMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return nil, err
	}
	if meta.Recent == nil {
		meta.Recent = map[string]time.Time{}
	}
	return &meta, nil
}

func (c *Checkouts) writeMeta(scope string, generation int64, meta *checkoutMeta) error {
	data, err := json.Marshal(meta)
	if err != nil {
		return err
	}
	path := filepath.Join(c.dir(scope, generation), "master.json")
	if err := os.WriteFile(path+".tmp", data, 0600); err != nil {
		return err
	}
	return checkoutRename(path+".tmp", path)
}

// A cleared volume starts a new generation; its older masters are never used again.
func (c *Checkouts) dropOtherGenerations(scope string, generation int64) {
	entries, err := os.ReadDir(filepath.Join(c.Root, scope))
	if err != nil {
		return
	}
	lock := c.lock(scope)
	lock.Lock()
	defer lock.Unlock()
	for _, entry := range entries {
		if entry.Name() != strconv.FormatInt(generation, 10) {
			_ = os.RemoveAll(filepath.Join(c.Root, scope, entry.Name()))
		}
	}
}

type checkoutMaster struct {
	scope, path string
	used        time.Time
}

func (c *Checkouts) masters() []checkoutMaster {
	paths, _ := filepath.Glob(filepath.Join(c.Root, "*", "*", "master.sparseimage"))
	masters := make([]checkoutMaster, 0, len(paths))
	for _, path := range paths {
		scope := filepath.Base(filepath.Dir(filepath.Dir(path)))
		info, err := os.Stat(path)
		if err != nil || !checkoutScope.MatchString(scope) {
			continue
		}
		masters = append(masters, checkoutMaster{scope: scope, path: path, used: info.ModTime()})
	}
	sort.Slice(masters, func(i, j int) bool { return masters[i].used.Before(masters[j].used) })
	return masters
}

// Maintain evicts masters no job cloned for a week.
func (c *Checkouts) Maintain() {
	if c == nil {
		return
	}
	c.mu.Lock()
	waiting := c.waiting
	c.waiting = nil
	c.mu.Unlock()
	for _, task := range waiting {
		c.Enqueue(task)
	}
	for _, master := range c.masters() {
		if c.now().Sub(master.used) > checkoutIdleFor {
			c.remove(master, false)
		}
	}
}

// Evict removes least recently used masters that no clone or build holds,
// until enough is gone or nothing evictable is left. It reports whether it
// removed anything; callers remeasure the filesystem afterwards.
func (c *Checkouts) Evict(enough func() bool) bool {
	if c == nil {
		return false
	}
	removed := false
	for _, master := range c.masters() {
		if enough() {
			break
		}
		if c.remove(master, true) {
			removed = true
		}
	}
	return removed
}

func (c *Checkouts) remove(master checkoutMaster, try bool) bool {
	if c.isBusy(master.scope) {
		return false
	}
	lock := c.lock(master.scope)
	if try {
		if !lock.TryLock() {
			return false
		}
	} else {
		lock.Lock()
	}
	defer lock.Unlock()
	return os.RemoveAll(filepath.Dir(master.path)) == nil
}

func (c *Checkouts) setBusy(scope string, busy bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.busy == nil {
		c.busy = map[string]bool{}
	}
	if busy {
		c.busy[scope] = true
	} else {
		delete(c.busy, scope)
	}
}

func (c *Checkouts) isBusy(scope string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.busy[scope]
}

func checkoutRename(src, dst string) error {
	sync := func(path string) error {
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()
		return f.Sync()
	}
	if err := sync(src); err != nil {
		return err
	}
	if err := os.Rename(src, dst); err != nil {
		return err
	}
	return sync(filepath.Dir(dst))
}

// ensureGitLFS installs the pinned git-lfs next to the masters. Hosts have no
// git-lfs of their own, and the populator never runs whatever is on PATH.
func (c *Checkouts) ensureGitLFS(ctx context.Context) error {
	bin := filepath.Join(c.Root, ".bin")
	marker := filepath.Join(bin, "git-lfs.sha256")
	if installed, err := os.ReadFile(marker); err == nil && string(installed) == gitLFSSHA256 {
		if _, err := os.Stat(filepath.Join(bin, "git-lfs")); err == nil {
			return nil
		}
	}
	download := c.Download
	if download == nil {
		download = downloadGitLFS
	}
	archive, err := download(ctx)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(archive)
	if hex.EncodeToString(sum[:]) != gitLFSSHA256 {
		return errors.New("git-lfs archive checksum mismatch")
	}
	reader, err := zip.NewReader(bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		return err
	}
	for _, file := range reader.File {
		if file.Name != gitLFSEntry {
			continue
		}
		if err := os.MkdirAll(bin, 0700); err != nil {
			return err
		}
		in, err := file.Open()
		if err != nil {
			return err
		}
		defer in.Close()
		tmp := filepath.Join(bin, "git-lfs.tmp")
		out, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0755)
		if err != nil {
			return err
		}
		_, err = io.Copy(out, io.LimitReader(in, 64<<20))
		if closeErr := out.Close(); err == nil {
			err = closeErr
		}
		if err != nil {
			return err
		}
		if err := checkoutRename(tmp, filepath.Join(bin, "git-lfs")); err != nil {
			return err
		}
		return os.WriteFile(marker, []byte(gitLFSSHA256), 0600)
	}
	return errors.New("git-lfs archive has no binary")
}

func downloadGitLFS(ctx context.Context) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, gitLFSURL, nil)
	if err != nil {
		return nil, err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("git-lfs download status %d", response.StatusCode)
	}
	return io.ReadAll(io.LimitReader(response.Body, 64<<20))
}
