package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	// CheckoutCapacity is the logical size of a checkout master image.
	CheckoutCapacity       = 60_000_000_000
	checkoutBuildRoom      = 20_000_000_000
	checkoutIngestRoom     = 10_000_000_000
	checkoutRecentFor      = 14 * 24 * time.Hour
	checkoutIdleFor        = 7 * 24 * time.Hour
	checkoutWaitFor        = time.Hour
	checkoutAbandonedAfter = time.Hour
	checkoutQueue          = 16
	checkoutIncomingDir    = ".incoming"
	checkoutVolumesDir     = ".volumes"
)

var checkoutScope = regexp.MustCompile(`^[a-f0-9]{64}$`)
var checkoutRepository = regexp.MustCompile(`^https://github\.com/[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$`)
var checkoutCommit = regexp.MustCompile(`^[a-f0-9]{40}$`)
var checkoutBranch = regexp.MustCompile(`^[A-Za-z0-9._/-]{1,255}$`)
var checkoutUse = regexp.MustCompile(`^[a-f0-9-]{36}$`)
var checkoutImageDigest = regexp.MustCompile(`^[a-f0-9]{40}$`)

// CheckoutImages is the filesystem image a checkout master lives in: an APFS
// sparse image on macOS, an ext4 image on a reflink filesystem on Linux.
type CheckoutImages interface {
	// MasterName is the file name of a master image.
	MasterName() string
	// Create formats an empty image of the given logical size.
	Create(ctx context.Context, path string, bytes int64) error
	// Clone makes a copy-on-write copy; it must fail rather than copy bytes.
	Clone(ctx context.Context, src, dst string) error
	Attach(ctx context.Context, image, mount string, readOnly bool) error
	// Detach unmounts cleanly or fails, so a master is never installed while written.
	Detach(ctx context.Context, image, mount string) error
	// Abandon forcibly unmounts what a failed build left mounted.
	Abandon(ctx context.Context, image, mount string)
	// Repository is where the working tree sits inside a mounted image.
	Repository(mount string) string
	// Own hands a built tree to the job's user.
	Own(ctx context.Context, repo string, uid int) error
}

// Checkouts keeps the host-built masters of checkout volumes: a repository's
// working tree at a default-branch commit (or, until one ran, the commit of the
// job that started the master) plus its .git and LFS objects. Only
// this type writes them. It builds them from what jobs export after their own
// checkout, never trusting that data: git verifies every object of the pack and
// the host hashes every LFS object, and the host writes the working tree and the
// index itself. A master is then published as the volume's HEAD, so other hosts
// restore it instead of waiting for a job of their own. Guests get CoW clones
// that are never published.
type Checkouts struct {
	Root   string
	Images CheckoutImages
	Run    func(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error)
	// Room reserves disk for a build until the returned release is called.
	Room func(context.Context, uint64) (func(), error)
	// InUse reports whether a job holds or is attaching a clone of a volume's
	// master. Pressure eviction skips those: the clone shares the master's blocks,
	// so removing it frees nothing, and an attaching job would lose its seed.
	InUse func(scope string) bool
	Now   func() time.Time
	// Tools installs what the populator runs before git is probed, if anything.
	Tools func(context.Context) error
	// Path is the PATH git runs with; Root/.bin, /usr/bin and /bin by default.
	Path string
	// Transfer publishes masters and restores the volume's HEAD.
	Transfer ImageTransfer
	Observe  Observer
	Log      *slog.Logger

	mu      sync.Mutex
	locks   map[string]*sync.Mutex
	pending map[string]CheckoutTask
	// waiting holds builds refused for disk room until a reconcile retries them.
	waiting map[string]CheckoutTask
	busy    map[string]bool
	queue   chan string
	ready   bool
}

type CheckoutTask struct {
	Scope            string
	Generation       int64
	CloneURL         string
	DefaultBranch    string
	Commit           string
	DefaultBranchJob bool
	// MayStartMaster lets the job's checkout (its commit, or its pull request's
	// test merge of it) start the lineage's master when it has no HEAD: the
	// server sets it for same-repository branches its runner profile saves from,
	// never for forks or events that run untrusted code.
	MayStartMaster bool
	// The job's use names the lineage a master is published to and restored from.
	Use            string
	BaseGeneration int64
	ImageDigest    string
	ContentDigest  string
	// UID owns the working tree; the volume's identity includes it.
	UID int
	// VolumeKey stays the same when the volume is cleared; Scope does not.
	VolumeKey string
	// Export holds what the job exported; a task without one restores the HEAD.
	Export string
	Since  time.Time
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

func (c *Checkouts) logError(err error, msg string, args ...any) {
	logger := c.Log
	if logger == nil {
		logger = slog.Default()
	}
	logger.Error(msg, append(args, "error", err)...)
}

func (c *Checkouts) run(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error) {
	if c.Run != nil {
		return c.Run(ctx, dir, env, name, args...)
	}
	return runCheckoutCommand(ctx, dir, env, name, args...)
}

func runCheckoutCommand(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error) {
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
	return filepath.Join(c.dir(scope, generation), c.Images.MasterName())
}

func (c *Checkouts) nextPath(scope string, generation int64) string {
	return filepath.Join(c.dir(scope, generation), "next"+filepath.Ext(c.Images.MasterName()))
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
func (c *Checkouts) Seed(ctx context.Context, slot Slot, dst string) error {
	if slot.Kind != KindCheckout {
		return errors.New("not a checkout")
	}
	lock := c.lock(slot.Scope)
	lock.Lock()
	defer lock.Unlock()
	master := c.Master(slot.Scope, slot.Generation)
	if master == "" {
		return errors.New("checkout master unavailable")
	}
	if err := c.Images.Clone(ctx, master, dst); err != nil {
		return err
	}
	now := c.now()
	return os.Chtimes(master, now, now)
}

// Start runs the single build worker until ctx ends. Builds stay off while the
// host has no working git or git-lfs; jobs then check out as they do today.
func (c *Checkouts) Start(ctx context.Context) {
	_ = os.RemoveAll(filepath.Join(c.Root, checkoutIncomingDir))
	for {
		err := c.Prepare(ctx)
		if err == nil {
			break
		}
		c.logError(err, "cached checkouts unavailable on this host; retrying in 10 minutes")
		select {
		case <-ctx.Done():
			return
		case <-time.After(10 * time.Minute):
		}
	}
	defer func() {
		c.mu.Lock()
		c.ready = false
		c.mu.Unlock()
	}()
	c.mu.Lock()
	queue := c.queue
	c.mu.Unlock()
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
				c.Process(ctx, task)
			}
		}
	}
}

// Prepare checks the host's tools and starts accepting requests. Start calls it
// until it succeeds.
func (c *Checkouts) Prepare(ctx context.Context) error {
	if c.Images == nil {
		return errors.New("no checkout image backend")
	}
	if err := os.MkdirAll(filepath.Join(c.Root, ".home"), 0700); err != nil {
		return err
	}
	if c.Tools != nil {
		if err := c.Tools(ctx); err != nil {
			return err
		}
	}
	for _, tool := range [][]string{{"git", "--version"}, {"git", "lfs", "version"}} {
		if _, err := c.run(ctx, c.Root, c.baseEnv(), tool[0], tool[1:]...); err != nil {
			return err
		}
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.queue == nil {
		c.queue = make(chan string, checkoutQueue)
	}
	c.ready = true
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

// Pending returns the request queued for a volume, if any.
func (c *Checkouts) Pending(scope string) (CheckoutTask, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	task, ok := c.pending[scope]
	return task, ok
}

// Queued is the number of volumes with a queued request.
func (c *Checkouts) Queued() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.queue)
}

// Enqueue asks for a build from a job's export, or for a restore of the HEAD.
// The newest request per volume wins; a full queue drops the request, it never
// blocks. A dropped or replaced request's export is removed.
func (c *Checkouts) Enqueue(task CheckoutTask) bool {
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
		c.pending = map[string]CheckoutTask{}
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

func (c *Checkouts) replace(previous, next CheckoutTask) {
	if previous.Export != next.Export {
		c.discard(previous)
	}
}

func (c *Checkouts) discard(task CheckoutTask) {
	if c != nil && task.Export != "" && filepath.Dir(task.Export) == filepath.Join(c.Root, checkoutIncomingDir) {
		_ = os.RemoveAll(task.Export)
	}
}

func (c *Checkouts) validTask(task CheckoutTask) bool {
	branch := task.DefaultBranch
	valid := checkoutScope.MatchString(task.Scope) && task.Generation >= 0 && checkoutRepository.MatchString(task.CloneURL) &&
		checkoutBranch.MatchString(branch) && !strings.Contains(branch, "..") && !strings.HasPrefix(branch, "-") &&
		!strings.HasPrefix(branch, "/") && !strings.HasSuffix(branch, "/") &&
		(task.Commit == "" || checkoutCommit.MatchString(task.Commit)) && checkoutUse.MatchString(task.Use) && task.BaseGeneration >= 0 &&
		task.UID >= 0
	if task.BaseGeneration > 0 {
		valid = valid && checkoutImageDigest.MatchString(task.ImageDigest) && checkoutOID.MatchString(task.ContentDigest)
	}
	if task.Export == "" {
		return valid && task.BaseGeneration > 0
	}
	return valid && filepath.Dir(task.Export) == filepath.Join(c.Root, checkoutIncomingDir)
}

// Process runs one request now: a build from an export, or a restore of the HEAD.
func (c *Checkouts) Process(ctx context.Context, task CheckoutTask) {
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
	done := c.Observe.Start(operation, source)
	var err error
	if task.Export == "" {
		err = c.restore(ctx, task, room)
	} else {
		err = c.build(ctx, task, cold, meta, room)
	}
	done(err)
	if errors.Is(err, ErrCapacity) && c.now().Sub(task.Since) < checkoutWaitFor {
		// The requesting job usually holds the room; every reconcile retries for a while.
		c.mu.Lock()
		if c.waiting == nil {
			c.waiting = map[string]CheckoutTask{}
		}
		if _, queued := c.pending[task.Scope]; !queued {
			c.waiting[task.Scope] = task
			keep = true
		}
		c.mu.Unlock()
		return
	}
	if err != nil {
		c.logError(err, "checkout master not updated", "operation", operation)
	}
}

func (c *Checkouts) build(ctx context.Context, task CheckoutTask, cold bool, meta *checkoutMeta, room uint64) (err error) {
	export, err := openCheckoutExport(task.Export)
	if err != nil {
		return err
	}
	defer export.Close()
	// A master starts from a default-branch commit, or from an eligible job's while
	// the lineage has no HEAD; other exports only add to one. Whether the eligible
	// job's export is its commit needs the export's objects, so ingest decides.
	if cold && !onDefault(task, export) && !mayStartLineage(task) {
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
	next := c.nextPath(task.Scope, task.Generation)
	mount := filepath.Join(dir, "next.mnt")
	c.Images.Abandon(ctx, next, mount)
	_ = os.Remove(next)
	defer os.Remove(next)
	if cold {
		meta = &checkoutMeta{BuiltAt: c.now(), Recent: map[string]time.Time{}}
		if err := c.Images.Create(ctx, next, CheckoutCapacity); err != nil {
			return err
		}
	} else if err := c.Images.Clone(ctx, c.masterPath(task.Scope, task.Generation), next); err != nil {
		return err
	}
	if err := os.MkdirAll(mount, 0700); err != nil {
		return err
	}
	if err := c.Images.Attach(ctx, next, mount, false); err != nil {
		return err
	}
	attached := true
	defer func() {
		if attached {
			c.Images.Abandon(context.WithoutCancel(ctx), next, mount)
		}
	}()
	repo := c.Images.Repository(mount)
	if err := os.MkdirAll(repo, 0755); err != nil {
		return err
	}
	moved, err := c.ingest(ctx, repo, export, task, cold, meta)
	if err != nil {
		return err
	}
	if err := c.Images.Own(ctx, repo, task.UID); err != nil {
		return err
	}
	if err := c.Images.Detach(ctx, next, mount); err != nil {
		return err
	}
	attached = false
	_ = os.Remove(mount)
	if err := c.install(task, next, meta); err != nil {
		return err
	}
	if moved {
		done := c.Observe.Start("checkout_publish", "remote")
		err := c.publish(ctx, task)
		done(err)
		if err != nil {
			c.logError(err, "checkout master not published")
		}
	}
	return nil
}

func (c *Checkouts) install(task CheckoutTask, next string, meta *checkoutMeta) error {
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
// the tip moved.
func (c *Checkouts) ingest(ctx context.Context, repo string, export *checkoutExport, task CheckoutTask, cold bool, meta *checkoutMeta) (bool, error) {
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
	defaultTip := onDefault(task, export)
	if defaultTip {
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
	// default-branch commit, or starts at an eligible job's checkout (its commit or
	// its pull request's test merge) when the lineage has no HEAD, and only when
	// all its LFS objects are here: a pointer left in the working tree would be
	// served as the file's content.
	tip := defaultTip
	if !tip && cold && mayStartLineage(task) {
		if tip, err = jobCheckout(git, export.Head, task.Commit); err != nil {
			return false, err
		}
	}
	if !tip || export.Head == meta.Tip || !complete {
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
	return true, nil
}

// onDefault reports whether the export is the server-verified commit of a
// default-branch job.
func onDefault(task CheckoutTask, export *checkoutExport) bool {
	return task.DefaultBranchJob && export.Head == task.Commit
}

// mayStartLineage reports whether the job may start a lineage that has no HEAD yet.
func mayStartLineage(task CheckoutTask) bool {
	return task.MayStartMaster && task.BaseGeneration == 0
}

// jobCheckout reports whether head is what the job checked out: its verified
// commit, or a pull request's test merge of it, which actions/checkout checks out
// instead and whose parents a depth-1 fetch leaves out. The raw commit object
// still names them, and shallow history does not hide them from cat-file.
func jobCheckout(git func(...string) ([]byte, error), head, commit string) (bool, error) {
	if head == commit {
		return true, nil
	}
	object, err := git("cat-file", "commit", head)
	if err != nil {
		return false, err
	}
	var parents []string
	for _, line := range strings.Split(string(object), "\n") {
		if line == "" {
			break
		}
		if parent, ok := strings.CutPrefix(line, "parent "); ok {
			parents = append(parents, parent)
		}
	}
	return len(parents) == 2 && (parents[0] == commit || parents[1] == commit), nil
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
func (c *Checkouts) restore(ctx context.Context, task CheckoutTask, room uint64) error {
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
	// The transfer resumes a partial download it finds at the same path, so the
	// path names the HEAD: a restart never appends another HEAD's archive to it.
	next := c.restorePath(task)
	mount := filepath.Join(dir, "next.mnt")
	c.discardOtherDownloads(ctx, dir, next, mount)
	c.Images.Abandon(ctx, next, mount)
	_ = os.Remove(next)
	defer os.Remove(next)
	if err := c.Transfer.Download(ctx, c.headSlot(task), next); err != nil {
		return err
	}
	if err := os.MkdirAll(mount, 0700); err != nil {
		return err
	}
	if err := c.Images.Attach(ctx, next, mount, true); err != nil {
		return err
	}
	repo := c.Images.Repository(mount)
	tip, err := c.run(ctx, repo, c.gitEnv(), "git", "rev-parse", "HEAD")
	var recent []byte
	if err == nil {
		// The publisher's job commits age out here from now on.
		recent, err = c.run(ctx, repo, c.gitEnv(), "git", "for-each-ref", "--format=%(objectname)", "refs/tuist/recent")
	}
	if detachErr := c.Images.Detach(ctx, next, mount); err == nil {
		err = detachErr
	}
	if err != nil {
		c.Images.Abandon(context.WithoutCancel(ctx), next, mount)
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
func (c *Checkouts) publish(ctx context.Context, task CheckoutTask) error {
	if c.Transfer == nil {
		return nil
	}
	archive := filepath.Join(c.dir(task.Scope, task.Generation), "master.zst")
	defer os.Remove(archive)
	digest, content, err := CompressImage(c.masterPath(task.Scope, task.Generation), archive)
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	_, err = c.Transfer.Publish(c.headSlot(task), archive, digest, content)
	if errors.Is(err, ErrConflict) {
		return nil
	}
	return err
}

func (c *Checkouts) headSlot(task CheckoutTask) Slot {
	return Slot{Identity: Identity{
		ID: task.Use, Scope: task.Scope, BaseGeneration: task.BaseGeneration,
		ImageDigest: task.ImageDigest, ContentDigest: task.ContentDigest,
	}}
}

func (c *Checkouts) baseEnv() []string {
	path := c.Path
	if path == "" {
		path = filepath.Join(c.Root, ".bin") + ":/usr/bin:/bin"
	}
	return []string{
		"PATH=" + path,
		"HOME=" + filepath.Join(c.Root, ".home"),
		"GIT_CONFIG_NOSYSTEM=1",
		"GIT_CONFIG_GLOBAL=/dev/null",
		"GIT_TERMINAL_PROMPT=0",
		"GIT_LFS_SKIP_SMUDGE=1",
	}
}

// gitEnv configures git-lfs for one command without touching the master's
// .git/config, which guests receive. The tree belongs to the job's user while the
// host runs git as another, which git otherwise refuses.
func (c *Checkouts) gitEnv() []string {
	settings := [][2]string{
		{"core.hooksPath", "/dev/null"},
		{"safe.directory", "*"},
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
func (c *Checkouts) Track(task CheckoutTask) {
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
	if c.Images == nil {
		return nil
	}
	paths, _ := filepath.Glob(filepath.Join(c.Root, "*", "*", c.Images.MasterName()))
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
	c.removeAbandonedDownloads()
}

// removeAbandonedDownloads deletes restore downloads no restore wrote for an
// hour: a running download keeps writing, and a restore that never comes back
// would otherwise keep its partial forever.
func (c *Checkouts) removeAbandonedDownloads() {
	downloads, _ := filepath.Glob(filepath.Join(c.Root, "*", "*", "restore-*"))
	for _, path := range downloads {
		scope := filepath.Base(filepath.Dir(filepath.Dir(path)))
		info, err := os.Stat(path)
		if err != nil || c.isBusy(scope) || c.now().Sub(info.ModTime()) < checkoutAbandonedAfter {
			continue
		}
		_ = os.Remove(path)
	}
}

// Evictable is what evicting every master no build holds would free.
func (c *Checkouts) Evictable(size func(string) (uint64, error)) uint64 {
	if c == nil {
		return 0
	}
	var total uint64
	for _, master := range c.masters() {
		if c.isBusy(master.scope) || c.inUse(master.scope) {
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
	if c.isBusy(master.scope) || (try && c.inUse(master.scope)) {
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

func (c *Checkouts) inUse(scope string) bool {
	return c.InUse != nil && c.InUse(scope)
}

// DiscardWaiting drops the exports of builds that are waiting for room, and
// reports how many it dropped. Newer exports take their place.
func (c *Checkouts) DiscardWaiting() int {
	if c == nil {
		return 0
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	dropped := 0
	for scope, task := range c.waiting {
		c.discard(task)
		delete(c.waiting, scope)
		dropped++
	}
	return dropped
}

// restorePath is where a restore downloads the volume's HEAD.
func (c *Checkouts) restorePath(task CheckoutTask) string {
	name := fmt.Sprintf("restore-%020d-%s%s", task.BaseGeneration, task.ContentDigest, filepath.Ext(c.Images.MasterName()))
	return filepath.Join(c.dir(task.Scope, task.Generation), name)
}

// discardOtherDownloads removes what earlier restores of other HEADs, or a build,
// left beside the master, so only this HEAD's own partial download is resumed.
func (c *Checkouts) discardOtherDownloads(ctx context.Context, dir, keep, mount string) {
	ext := filepath.Ext(c.Images.MasterName())
	candidates, _ := filepath.Glob(filepath.Join(dir, "restore-*"))
	candidates = append(candidates, filepath.Join(dir, "next"+ext+".part"))
	for _, path := range candidates {
		if path == keep || path == keep+".part" {
			continue
		}
		if image := strings.TrimSuffix(path, ".part"); image == path {
			c.Images.Abandon(ctx, image, mount)
		}
		_ = os.Remove(path)
	}
}
