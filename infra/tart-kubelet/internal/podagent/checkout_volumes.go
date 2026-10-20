package podagent

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
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
	checkoutCapacity    = 60_000_000_000
	checkoutBuildRoom   = 20_000_000_000
	checkoutIngestRoom  = 10_000_000_000
	checkoutRecentFor   = 14 * 24 * time.Hour
	checkoutIdleFor     = 7 * 24 * time.Hour
	checkoutWaitFor     = time.Hour
	checkoutQueue       = 16
	checkoutIncomingDir = ".incoming"
	checkoutVolumesDir  = ".volumes"

	// The git-lfs the populator runs, pinned and verified before it is used.
	gitLFSURL    = "https://github.com/git-lfs/git-lfs/releases/download/v3.8.0/git-lfs-darwin-arm64-v3.8.0.zip"
	gitLFSSHA256 = "caff76a7d070d8160c89bc39b6e85d98f24135b6fed038a3b4de2590d25102d8"
	gitLFSEntry  = "git-lfs-3.8.0/git-lfs"
)

var checkoutScope = regexp.MustCompile(`^[a-f0-9]{64}$`)
var checkoutRepository = regexp.MustCompile(`^https://github\.com/[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$`)
var checkoutCommit = regexp.MustCompile(`^[a-f0-9]{40}$`)
var checkoutBranch = regexp.MustCompile(`^[A-Za-z0-9._/-]{1,255}$`)
var checkoutUse = regexp.MustCompile(`^[a-f0-9-]{36}$`)
var checkoutImageDigest = regexp.MustCompile(`^[a-f0-9]{40}$`)

// Checkouts keeps the host-built masters of checkout volumes: a repository's
// working tree at a default-branch commit plus its .git and LFS objects. Only
// this type writes them. It builds them from what jobs export after their own
// checkout, never trusting that data: git verifies every object of the pack and
// the host hashes every LFS object, and the host writes the working tree and the
// index itself. A master is then published as the volume's HEAD, so other hosts
// restore it instead of waiting for a job of their own. Guests get CoW clones
// that are never published.
type Checkouts struct {
	Root string
	Run  func(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error)
	// Room reserves disk for a build until the returned release is called.
	Room func(context.Context, uint64) (func(), error)
	Now  func() time.Time
	// Download fetches the pinned git-lfs release archive.
	Download func(context.Context) ([]byte, error)
	// Transfer publishes masters and restores the volume's HEAD.
	Transfer cachevolumes.ImageTransfer

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
	Scope            string
	Generation       int64
	CloneURL         string
	DefaultBranch    string
	Commit           string
	DefaultBranchJob bool
	// The job's use names the lineage a master is published to and restored from.
	Use            string
	BaseGeneration int64
	ImageDigest    string
	ContentDigest  string
	// Export holds what the job exported; a task without one restores the HEAD.
	// VolumeKey stays the same when the volume is cleared; Scope does not.
	VolumeKey string
	Export    string
	Since     time.Time
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

// Incoming is where the host moves a finished job's export before it builds from it.
func (c *Checkouts) Incoming(name string) string {
	return filepath.Join(c.Root, checkoutIncomingDir, name)
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
	_ = os.RemoveAll(filepath.Join(c.Root, checkoutIncomingDir))
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

// Ready reports whether builds run on this host, so callers keep no exports otherwise.
func (c *Checkouts) Ready() bool {
	if c == nil {
		return false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.ready
}

// Enqueue asks for a build from a job's export, or for a restore of the HEAD.
// The newest request per volume wins; a full queue drops the request, it never
// blocks. A dropped or replaced request's export is removed.
func (c *Checkouts) Enqueue(task checkoutTask) bool {
	if c == nil || !c.validTask(task) {
		c.discard(task)
		return false
	}
	if task.Since.IsZero() {
		task.Since = c.now()
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.ready || c.queue == nil {
		c.discard(task)
		return false
	}
	if c.pending == nil {
		c.pending = map[string]checkoutTask{}
	}
	if waiting, ok := c.waiting[task.Scope]; ok {
		delete(c.waiting, task.Scope)
		c.replace(waiting, task)
	}
	previous, queued := c.pending[task.Scope]
	if queued && previous.Export != "" && task.Export == "" {
		// A restore never replaces a job's export: the export builds on whatever is there.
		return true
	}
	c.pending[task.Scope] = task
	if queued {
		c.replace(previous, task)
		return true
	}
	select {
	case c.queue <- task.Scope:
		return true
	default:
		delete(c.pending, task.Scope)
		c.discard(task)
		return false
	}
}

func (c *Checkouts) replace(previous, next checkoutTask) {
	if previous.Export != next.Export {
		c.discard(previous)
	}
}

func (c *Checkouts) discard(task checkoutTask) {
	if c != nil && task.Export != "" && filepath.Dir(task.Export) == filepath.Join(c.Root, checkoutIncomingDir) {
		_ = os.RemoveAll(task.Export)
	}
}

func (c *Checkouts) validTask(task checkoutTask) bool {
	branch := task.DefaultBranch
	valid := checkoutScope.MatchString(task.Scope) && task.Generation >= 0 && checkoutRepository.MatchString(task.CloneURL) &&
		checkoutBranch.MatchString(branch) && !strings.Contains(branch, "..") && !strings.HasPrefix(branch, "-") &&
		!strings.HasPrefix(branch, "/") && !strings.HasSuffix(branch, "/") &&
		(task.Commit == "" || checkoutCommit.MatchString(task.Commit)) && checkoutUse.MatchString(task.Use) && task.BaseGeneration >= 0
	if task.BaseGeneration > 0 {
		valid = valid && checkoutImageDigest.MatchString(task.ImageDigest) && checkoutOID.MatchString(task.ContentDigest)
	}
	if task.Export == "" {
		return valid && task.BaseGeneration > 0
	}
	return valid && filepath.Dir(task.Export) == filepath.Join(c.Root, checkoutIncomingDir)
}

func (c *Checkouts) process(ctx context.Context, task checkoutTask) {
	if task.Since.IsZero() {
		task.Since = c.now()
	}
	keep := false
	defer func() {
		if !keep {
			c.discard(task)
		}
	}()
	meta, _ := c.readMeta(task.Scope, task.Generation)
	cold := c.Master(task.Scope, task.Generation) == "" || meta == nil
	operation, source, budget, room := "checkout_ingest", "local", 15*time.Minute, uint64(checkoutIngestRoom)
	switch {
	case task.Export == "" && !cold:
		return
	case task.Export == "":
		operation, source, budget, room = "checkout_restore", "remote", 45*time.Minute, uint64(checkoutBuildRoom)
	case cold:
		operation, budget, room = "checkout_build", 45*time.Minute, uint64(checkoutBuildRoom)
	}
	ctx, cancel := context.WithTimeout(ctx, budget)
	defer cancel()
	done := cachevolumes.Observer(observeCustomCache).Start(operation, source)
	var err error
	if task.Export == "" {
		err = c.restore(ctx, task, room)
	} else {
		err = c.build(ctx, task, cold, meta, room)
	}
	done(err)
	if errors.Is(err, cachevolumes.ErrCapacity) && c.now().Sub(task.Since) < checkoutWaitFor {
		// The requesting job usually holds the room; every reconcile retries for a while.
		c.mu.Lock()
		if c.waiting == nil {
			c.waiting = map[string]checkoutTask{}
		}
		if _, queued := c.pending[task.Scope]; !queued {
			c.waiting[task.Scope] = task
			keep = true
		}
		c.mu.Unlock()
		return
	}
	if err != nil {
		log.FromContext(ctx).Error(err, "checkout master not updated", "operation", operation)
	}
}

func (c *Checkouts) build(ctx context.Context, task checkoutTask, cold bool, meta *checkoutMeta, room uint64) (err error) {
	export, err := openCheckoutExport(task.Export)
	if err != nil {
		return err
	}
	defer export.Close()
	// A master only starts from a default-branch commit; other exports only add to one.
	if cold && !(task.DefaultBranchJob && export.Head == task.Commit) {
		return nil
	}
	// The image grows by about twice the export: its objects and their checked-out files.
	room = max(room, 2*export.Bytes)
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
	if cold {
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
	moved, err := c.ingest(ctx, mount, export, task, cold, meta)
	if err != nil {
		return err
	}
	if err := c.detachStrict(ctx, mount); err != nil {
		return err
	}
	attached = false
	_ = os.Remove(mount)
	if err := c.install(task, next, meta); err != nil {
		return err
	}
	if moved && task.DefaultBranchJob {
		done := cachevolumes.Observer(observeCustomCache).Start("checkout_publish", "remote")
		err := c.publish(ctx, task)
		done(err)
		if err != nil {
			log.FromContext(ctx).Error(err, "checkout master not published")
		}
	}
	return nil
}

func (c *Checkouts) install(task checkoutTask, next string, meta *checkoutMeta) error {
	lock := c.lock(task.Scope)
	lock.Lock()
	defer lock.Unlock()
	if err := checkoutRename(next, c.masterPath(task.Scope, task.Generation)); err != nil {
		return err
	}
	return c.writeMeta(task.Scope, task.Generation, meta)
}

// ingest adds a job's export to the mounted master and, when the export's commit
// should become the tip, writes that commit's working tree. It reports whether
// the tip moved to a default-branch commit.
func (c *Checkouts) ingest(ctx context.Context, repo string, export *checkoutExport, task checkoutTask, cold bool, meta *checkoutMeta) (bool, error) {
	git := func(args ...string) ([]byte, error) { return c.run(ctx, repo, c.gitEnv(), "git", args...) }
	if cold {
		if _, err := git("init", "-q", "."); err != nil {
			return false, err
		}
		if _, err := git("remote", "add", "origin", task.CloneURL); err != nil {
			return false, err
		}
		for _, setting := range [][2]string{{"core.checkStat", "minimal"}, {"core.trustctime", "false"}} {
			if _, err := git("config", setting[0], setting[1]); err != nil {
				return false, err
			}
		}
		// The guest's fseventsd may recreate this directory; keep the tree clean.
		if err := os.WriteFile(filepath.Join(repo, ".git", "info", "exclude"), []byte("/.fseventsd/\n"), 0644); err != nil {
			return false, err
		}
	} else if _, err := git("remote", "set-url", "origin", task.CloneURL); err != nil {
		return false, err
	}
	// The boundary goes first: `index-pack --strict` refuses links to commits it
	// was told nothing about, and the parents of a shallow commit are absent.
	if err := c.addShallow(git, repo, export.Shallow); err != nil {
		return false, err
	}
	if err := c.addPack(git, repo, export); err != nil {
		return false, err
	}
	if err := c.pruneShallow(git, repo); err != nil {
		return false, err
	}
	// The commit is only usable when every object it reaches is now present.
	if _, err := git("rev-list", "--quiet", "--objects", export.Head); err != nil {
		return false, fmt.Errorf("checkout export is incomplete: %w", err)
	}
	if _, err := git("update-ref", "refs/tuist/recent/"+export.Head, export.Head); err != nil {
		return false, err
	}
	meta.Recent[export.Head] = c.now()
	for commit, at := range meta.Recent {
		if c.now().Sub(at) > checkoutRecentFor {
			_, _ = git("update-ref", "-d", "refs/tuist/recent/"+commit)
			delete(meta.Recent, commit)
		}
	}
	// Branches stay remote-tracking: actions/checkout deletes local branches
	// before it fetches, and the refs it keeps are what it advertises as haves.
	onDefault := task.DefaultBranchJob && export.Head == task.Commit
	if onDefault {
		if _, err := git("update-ref", "refs/remotes/origin/"+task.DefaultBranch, export.Head); err != nil {
			return false, err
		}
	}
	// Only LFS objects the exported commit references are kept: anything else in
	// an export would take disk and be published without ever being used.
	listing, err := git("lfs", "ls-files", "--long", export.Head)
	if err != nil {
		return false, err
	}
	exported := map[string]bool{}
	for _, oid := range export.LFS {
		exported[oid] = true
	}
	store := filepath.Join(repo, ".git", "lfs", "objects")
	complete := true
	for _, oid := range lfsPointers(listing) {
		if exported[oid] {
			if err := export.copyLFS(oid, store); err != nil {
				return false, err
			}
		}
		if _, err := os.Stat(filepath.Join(store, oid[:2], oid[2:4], oid)); err != nil {
			complete = false
		}
	}
	// The tip's tree is what every later job is handed, so it only moves to a
	// default-branch commit, and only when all its LFS objects are here: a pointer
	// left in the working tree would be served as the file's content.
	if !onDefault || export.Head == meta.Tip || !complete {
		if cold {
			return false, errors.New("checkout export cannot start a master")
		}
		_, _ = git("gc", "--auto", "--quiet")
		return false, nil
	}
	if _, err := git("checkout", "-q", "--detach", "--force", export.Head); err != nil {
		return false, err
	}
	if _, err := git("lfs", "checkout"); err != nil {
		return false, err
	}
	// Record the stat data of smudged files in an index written after their
	// mtimes. An entry modified in the second its index was written is racily
	// clean: git rehashes it later, and in a guest that has not configured the
	// LFS filter yet (actions/checkout runs its clean and reset first) that turns
	// LFS files back into pointers.
	select {
	case <-ctx.Done():
		return false, ctx.Err()
	case <-time.After(time.Until(c.now().Truncate(time.Second).Add(1100 * time.Millisecond))):
	}
	if _, err := git("update-index", "-q", "--really-refresh"); err != nil {
		return false, err
	}
	_, _ = git("gc", "--auto", "--quiet")
	meta.Tip = export.Head
	meta.RefreshedAt = c.now()
	return onDefault, nil
}

// addPack lets git index the exported pack: `--strict` hashes every object and
// checks its format, as for a push, so nothing unverified enters the store.
func (c *Checkouts) addPack(git func(...string) ([]byte, error), repo string, export *checkoutExport) error {
	packs := filepath.Join(repo, ".git", "objects", "pack")
	if err := os.MkdirAll(packs, 0755); err != nil {
		return err
	}
	pack := filepath.Join(packs, "ingest.pack")
	defer os.Remove(pack)
	defer os.Remove(filepath.Join(packs, "ingest.idx"))
	defer os.Remove(filepath.Join(packs, "ingest.rev"))
	if err := export.copyPack(pack); err != nil {
		return err
	}
	out, err := git("index-pack", "--strict", pack)
	if err != nil {
		return err
	}
	name := strings.TrimSpace(string(out))
	if fields := strings.Fields(name); len(fields) > 0 {
		name = fields[len(fields)-1]
	}
	if !checkoutCommit.MatchString(name) {
		return errors.New("unexpected index-pack output")
	}
	for _, ext := range []string{".pack", ".idx", ".rev"} {
		src := filepath.Join(packs, "ingest"+ext)
		if _, err := os.Stat(src); err != nil {
			continue
		}
		if err := os.Rename(src, filepath.Join(packs, "pack-"+name+ext)); err != nil {
			return err
		}
	}
	return nil
}

// addShallow adds the export's shallow boundary to the master's.
func (c *Checkouts) addShallow(_ func(...string) ([]byte, error), repo string, commits []string) error {
	known := readShallow(repo)
	for _, commit := range commits {
		known[commit] = true
	}
	return writeShallow(repo, known)
}

// pruneShallow keeps the boundary to commits the master holds, so an export
// cannot leave names of commits that never arrived.
func (c *Checkouts) pruneShallow(git func(...string) ([]byte, error), repo string) error {
	known := readShallow(repo)
	for commit := range known {
		if _, err := git("cat-file", "-e", commit+"^{commit}"); err != nil {
			delete(known, commit)
		}
	}
	return writeShallow(repo, known)
}

func readShallow(repo string) map[string]bool {
	known := map[string]bool{}
	if data, err := os.ReadFile(filepath.Join(repo, ".git", "shallow")); err == nil {
		for _, line := range strings.Fields(string(data)) {
			if checkoutCommit.MatchString(line) {
				known[line] = true
			}
		}
	}
	return known
}

func writeShallow(repo string, known map[string]bool) error {
	path := filepath.Join(repo, ".git", "shallow")
	if len(known) == 0 {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	lines := make([]string, 0, len(known))
	for commit := range known {
		lines = append(lines, commit)
	}
	sort.Strings(lines)
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0644)
}

// restore downloads the volume's HEAD into this host's master. It was published
// by a host from verified exports, and its archive is checked against the HEAD's
// digest before it is installed.
func (c *Checkouts) restore(ctx context.Context, task checkoutTask, room uint64) error {
	if c.Transfer == nil {
		return errors.New("checkout transfer unavailable")
	}
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
	if err := c.Transfer.Download(ctx, c.headSlot(task), next); err != nil {
		return err
	}
	if err := os.MkdirAll(mount, 0700); err != nil {
		return err
	}
	if _, err := c.run(ctx, dir, nil, "hdiutil", "attach", next, "-readonly", "-nobrowse", "-noautoopen", "-quiet", "-mountpoint", mount); err != nil {
		return err
	}
	tip, err := c.run(ctx, mount, c.gitEnv(), "git", "rev-parse", "HEAD")
	var recent []byte
	if err == nil {
		// The publisher's job commits age out here from now on.
		recent, err = c.run(ctx, mount, c.gitEnv(), "git", "for-each-ref", "--format=%(objectname)", "refs/tuist/recent")
	}
	if detachErr := c.detachStrict(ctx, mount); err == nil {
		err = detachErr
	}
	if err != nil {
		return err
	}
	_ = os.Remove(mount)
	meta := &checkoutMeta{Tip: strings.TrimSpace(string(tip)), BuiltAt: c.now(), RefreshedAt: c.now(), Recent: map[string]time.Time{}}
	for _, commit := range strings.Fields(string(recent)) {
		if checkoutCommit.MatchString(commit) {
			meta.Recent[commit] = c.now()
		}
	}
	return c.install(task, next, meta)
}

// publish uploads the master as the volume's next HEAD under the job's use.
// Another host publishing first is not an error: its master is as good.
func (c *Checkouts) publish(ctx context.Context, task checkoutTask) error {
	if c.Transfer == nil {
		return nil
	}
	archive := filepath.Join(c.dir(task.Scope, task.Generation), "master.zst")
	defer os.Remove(archive)
	digest, content, err := cachevolumes.CompressImage(c.masterPath(task.Scope, task.Generation), archive)
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	_, err = c.Transfer.Publish(c.headSlot(task), archive, digest, content)
	if errors.Is(err, cachevolumes.ErrConflict) {
		return nil
	}
	return err
}

func (c *Checkouts) headSlot(task checkoutTask) cachevolumes.Slot {
	return cachevolumes.Slot{Identity: cachevolumes.Identity{
		ID: task.Use, Scope: task.Scope, BaseGeneration: task.BaseGeneration,
		ImageDigest: task.ImageDigest, ContentDigest: task.ContentDigest,
	}}
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

// gitEnv configures git-lfs for one command without touching the master's
// .git/config, which guests receive.
func (c *Checkouts) gitEnv() []string {
	settings := [][2]string{
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

// Track records the scope a volume uses on this host. Clearing a volume gives it
// a new scope, so the copies kept under the previous one are dropped.
func (c *Checkouts) Track(task checkoutTask) {
	if c == nil || !checkoutScope.MatchString(task.VolumeKey) || !checkoutScope.MatchString(task.Scope) {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	dir := filepath.Join(c.Root, checkoutVolumesDir)
	path := filepath.Join(dir, task.VolumeKey)
	previous, _ := os.ReadFile(path)
	if string(previous) == task.Scope {
		return
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return
	}
	if err := os.WriteFile(path, []byte(task.Scope), 0600); err != nil {
		return
	}
	if old := string(previous); checkoutScope.MatchString(old) {
		go c.removeScope(old)
	}
}

func (c *Checkouts) removeScope(scope string) {
	lock := c.lock(scope)
	lock.Lock()
	defer lock.Unlock()
	if !c.isBusy(scope) {
		_ = os.RemoveAll(filepath.Join(c.Root, scope))
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

// Evictable is what evicting every master no build holds would free.
func (c *Checkouts) Evictable(size func(string) (uint64, error)) uint64 {
	if c == nil {
		return 0
	}
	var total uint64
	for _, master := range c.masters() {
		if c.isBusy(master.scope) {
			continue
		}
		if bytes, err := size(master.path); err == nil {
			total += bytes
		}
	}
	return total
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
	lock := c.lock(master.scope)
	if try {
		if !lock.TryLock() {
			return false
		}
	} else {
		lock.Lock()
	}
	defer lock.Unlock()
	// Busy is set under this lock, so a build that started cannot lose its directory.
	if c.isBusy(master.scope) {
		return false
	}
	return os.RemoveAll(filepath.Dir(master.path)) == nil
}

func (c *Checkouts) setBusy(scope string, busy bool) {
	if busy {
		lock := c.lock(scope)
		lock.Lock()
		defer lock.Unlock()
	}
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
