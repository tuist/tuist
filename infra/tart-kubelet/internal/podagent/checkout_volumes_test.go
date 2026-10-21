package podagent

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	ktesting "k8s.io/client-go/testing"
)

var checkoutTestScope = strings.Repeat("a", 64)

const checkoutTestCommit = "0123456789abcdef0123456789abcdef01234567"
const checkoutTestOther = "fedcba9876543210fedcba9876543210fedcba98"
const checkoutTestUse = "11111111-1111-4111-8111-111111111111"

type checkoutCall struct {
	dir  string
	env  []string
	name string
	args []string
}

// fakeCheckoutHost stands in for hdiutil, cp and git. It creates the files the
// real tools would, so the master lifecycle runs end to end on any platform.
type fakeCheckoutHost struct {
	mu    sync.Mutex
	calls []checkoutCall
	fail  func(checkoutCall) bool
	// lfs is what `git lfs ls-files --long` lists for any commit.
	lfs []string
}

func (f *fakeCheckoutHost) run(_ context.Context, dir string, env []string, name string, args ...string) ([]byte, error) {
	call := checkoutCall{dir: dir, env: env, name: name, args: args}
	f.mu.Lock()
	f.calls = append(f.calls, call)
	fail := f.fail
	lfs := append([]string(nil), f.lfs...)
	f.mu.Unlock()
	if fail != nil && fail(call) {
		return nil, os.ErrInvalid
	}
	switch {
	case name == "hdiutil" && args[0] == "create":
		return nil, os.WriteFile(args[len(args)-1], []byte("image"), 0600)
	case name == "cp":
		data, err := os.ReadFile(args[1])
		if err != nil {
			return nil, err
		}
		return nil, os.WriteFile(args[2], data, 0600)
	case name == "git" && args[0] == "init":
		return nil, os.MkdirAll(filepath.Join(dir, ".git", "info"), 0755)
	case name == "git" && args[0] == "index-pack":
		pack := args[len(args)-1]
		return []byte(strings.Repeat("9", 40) + "\n"), os.WriteFile(strings.TrimSuffix(pack, ".pack")+".idx", nil, 0644)
	case name == "git" && args[0] == "rev-parse":
		return []byte(checkoutTestCommit + "\n"), nil
	case name == "git" && len(args) > 1 && args[0] == "lfs" && args[1] == "ls-files":
		var out []string
		for _, oid := range lfs {
			out = append(out, oid+" * file-"+oid[:4])
		}
		return []byte(strings.Join(out, "\n")), nil
	}
	return nil, nil
}

func (f *fakeCheckoutHost) commands() []checkoutCall {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]checkoutCall(nil), f.calls...)
}

func (f *fakeCheckoutHost) reset() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = nil
}

func (f *fakeCheckoutHost) ran(name string, args ...string) bool {
	for _, call := range f.commands() {
		if call.name == name && len(call.args) >= len(args) && strings.Join(call.args[:len(args)], " ") == strings.Join(args, " ") {
			return true
		}
	}
	return false
}

// fakeCheckoutTransfer records publications and serves a HEAD for restores.
type fakeCheckoutTransfer struct {
	published []cachevolumes.Slot
	downloads []cachevolumes.Slot
	conflict  bool
}

func (f *fakeCheckoutTransfer) Download(_ context.Context, slot cachevolumes.Slot, path string) error {
	f.downloads = append(f.downloads, slot)
	return os.WriteFile(path, []byte("head"), 0600)
}

func (f *fakeCheckoutTransfer) Publish(slot cachevolumes.Slot, path, _, _ string) (int64, error) {
	if _, err := os.Stat(path); err != nil {
		return 0, err
	}
	if f.conflict {
		return 0, cachevolumes.ErrConflict
	}
	f.published = append(f.published, slot)
	return slot.BaseGeneration + 1, nil
}

func newCheckouts(t *testing.T) (*Checkouts, *fakeCheckoutHost) {
	t.Helper()
	host := &fakeCheckoutHost{}
	return &Checkouts{Root: t.TempDir(), Run: host.run}, host
}

func lfsOID(content string) string {
	sum := sha256.Sum256([]byte(content))
	return hex.EncodeToString(sum[:])
}

// exportFrom writes what a guest's teardown hands the host, already moved to
// the incoming directory, and returns a task to build from it.
func exportFrom(t *testing.T, c *Checkouts, name, head string, lfs map[string]string) checkoutTask {
	t.Helper()
	dir := c.Incoming(name)
	if err := os.MkdirAll(filepath.Join(dir, "lfs"), 0755); err != nil {
		t.Fatal(err)
	}
	for oid, content := range lfs {
		if err := os.WriteFile(filepath.Join(dir, "lfs", oid), []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	for file, content := range map[string]string{"head": head + "\n", "pack": "PACK", "shallow": head + "\n"} {
		if err := os.WriteFile(filepath.Join(dir, file), []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	task := checkoutTestTask()
	task.Export = dir
	return task
}

func checkoutTestTask() checkoutTask {
	return checkoutTask{
		Scope: checkoutTestScope, Generation: 1, CloneURL: "https://github.com/org/repo", DefaultBranch: "main",
		Commit: checkoutTestCommit, DefaultBranchJob: true, Use: checkoutTestUse,
	}
}

func lfsStore(c *Checkouts) string {
	return filepath.Join(c.dir(checkoutTestScope, 1), "next.mnt", ".git", "lfs", "objects")
}

func TestCheckoutColdBuildCreatesTheMasterFromAJobsExport(t *testing.T) {
	c, host := newCheckouts(t)
	content := "large file"
	oid := lfsOID(content)
	host.lfs = []string{oid}
	task := exportFrom(t, c, "job", checkoutTestCommit, map[string]string{oid: content})

	c.process(context.Background(), task)

	if c.Master(checkoutTestScope, 1) == "" {
		t.Fatal("no master after a cold build")
	}
	if !host.ran("hdiutil", "create") || host.ran("cp") {
		t.Fatal("a cold build formats a new image")
	}
	for _, want := range [][]string{
		{"remote", "add", "origin", "https://github.com/org/repo"},
		{"config", "core.checkStat", "minimal"},
		{"index-pack", "--strict"},
		{"rev-list", "--quiet", "--objects", checkoutTestCommit},
		{"update-ref", "refs/tuist/recent/" + checkoutTestCommit, checkoutTestCommit},
		{"update-ref", "refs/remotes/origin/main", checkoutTestCommit},
		{"checkout", "-q", "--detach", "--force", checkoutTestCommit},
		{"lfs", "checkout"},
		{"update-index", "-q", "--really-refresh"},
	} {
		if !host.ran("git", want...) {
			t.Fatalf("missing git %v", want)
		}
	}
	for _, call := range host.commands() {
		if call.name == "git" && (call.args[0] == "fetch" || call.args[0] == "-c") {
			t.Fatalf("the host must never reach a remote: %v", call.args)
		}
	}
	if data, err := os.ReadFile(filepath.Join(lfsStore(c), oid[:2], oid[2:4], oid)); err != nil || string(data) != content {
		t.Fatal("the verified LFS object was not installed")
	}
	if shallow, _ := os.ReadFile(filepath.Join(c.dir(checkoutTestScope, 1), "next.mnt", ".git", "shallow")); !strings.Contains(string(shallow), checkoutTestCommit) {
		t.Fatal("the export's shallow boundary was not recorded")
	}
	meta, err := c.readMeta(checkoutTestScope, 1)
	if err != nil || meta.Tip != checkoutTestCommit || meta.Recent[checkoutTestCommit].IsZero() {
		t.Fatalf("meta %+v %v", meta, err)
	}
	if _, err := os.Stat(task.Export); !os.IsNotExist(err) {
		t.Fatal("the consumed export was kept")
	}
}

func TestCheckoutLFSObjectsMustHashToTheirNames(t *testing.T) {
	c, host := newCheckouts(t)
	oid := lfsOID("the real content")
	host.lfs = []string{oid}
	c.process(context.Background(), exportFrom(t, c, "job", checkoutTestCommit, map[string]string{oid: "forged content"}))
	if c.Master(checkoutTestScope, 1) != "" {
		t.Fatal("built a master from a forged LFS object")
	}
	if _, err := os.Stat(filepath.Join(lfsStore(c), oid[:2], oid[2:4], oid)); !os.IsNotExist(err) {
		t.Fatal("installed a forged LFS object")
	}
}

func TestCheckoutIncompleteExportsAreRefused(t *testing.T) {
	c, host := newCheckouts(t)
	host.fail = func(call checkoutCall) bool { return call.name == "git" && call.args[0] == "rev-list" }
	c.process(context.Background(), exportFrom(t, c, "job", checkoutTestCommit, nil))
	if c.Master(checkoutTestScope, 1) != "" {
		t.Fatal("built a master whose commit is missing objects")
	}
}

func TestCheckoutTipOnlyMovesToCompleteDefaultBranchCommits(t *testing.T) {
	c, host := newCheckouts(t)
	c.process(context.Background(), exportFrom(t, c, "first", checkoutTestCommit, nil))

	// A pull request's objects are kept, but its commit never becomes the tip.
	host.reset()
	branch := exportFrom(t, c, "branch", checkoutTestOther, nil)
	branch.DefaultBranchJob = false
	c.process(context.Background(), branch)
	if !host.ran("git", "index-pack") || !host.ran("git", "update-ref", "refs/tuist/recent/"+checkoutTestOther) || host.ran("git", "checkout") {
		t.Fatal("a branch job adds its objects without moving the tip")
	}
	if host.ran("git", "update-ref", "refs/remotes/origin/main") {
		t.Fatal("a branch job moved the default branch")
	}
	if meta, _ := c.readMeta(checkoutTestScope, 1); meta.Tip != checkoutTestCommit {
		t.Fatalf("tip %s", meta.Tip)
	}

	// A default-branch commit whose LFS objects are not all here stays a ref only.
	host.reset()
	host.lfs = []string{lfsOID("missing")}
	next := exportFrom(t, c, "next", checkoutTestOther, nil)
	next.Commit = checkoutTestOther
	c.process(context.Background(), next)
	if host.ran("git", "checkout") {
		t.Fatal("moved the tip to a commit whose LFS objects are missing")
	}

	host.reset()
	host.lfs = nil
	next = exportFrom(t, c, "complete", checkoutTestOther, nil)
	next.Commit = checkoutTestOther
	c.process(context.Background(), next)
	if !host.ran("git", "checkout", "-q", "--detach", "--force", checkoutTestOther) || !host.ran("cp", "-c", c.masterPath(checkoutTestScope, 1)) {
		t.Fatal("a complete default-branch commit becomes the tip of a clone of the master")
	}
}

func TestCheckoutColdBuildNeedsEveryLFSObjectOfItsCommit(t *testing.T) {
	c, host := newCheckouts(t)
	host.lfs = []string{lfsOID("missing")}
	c.process(context.Background(), exportFrom(t, c, "job", checkoutTestCommit, nil))
	if c.Master(checkoutTestScope, 1) != "" {
		t.Fatal("a master with LFS pointers in its working tree would serve them as content")
	}
}

func TestCheckoutPublishesMastersOfDefaultBranchCommits(t *testing.T) {
	c, _ := newCheckouts(t)
	transfer := &fakeCheckoutTransfer{}
	c.Transfer = transfer
	branch := exportFrom(t, c, "branch", checkoutTestCommit, nil)
	branch.DefaultBranchJob = false
	c.process(context.Background(), branch)
	if len(transfer.published) != 0 {
		t.Fatal("published a master built from a branch job")
	}

	task := exportFrom(t, c, "main", checkoutTestOther, nil)
	task.Commit, task.BaseGeneration = checkoutTestOther, 0
	c.process(context.Background(), task)
	if len(transfer.published) != 1 || transfer.published[0].ID != checkoutTestUse || transfer.published[0].Scope != checkoutTestScope {
		t.Fatalf("published %+v", transfer.published)
	}
	if _, err := os.Stat(filepath.Join(c.dir(checkoutTestScope, 1), "master.zst")); !os.IsNotExist(err) {
		t.Fatal("left the archive behind")
	}

	transfer.conflict = true
	again := exportFrom(t, c, "again", checkoutTestCommit, nil)
	c.process(context.Background(), again)
	if c.Master(checkoutTestScope, 1) == "" {
		t.Fatal("another host publishing first must not cost this host its master")
	}
}

func TestCheckoutRestoresTheHeadOnAHostWithoutAMaster(t *testing.T) {
	c, host := newCheckouts(t)
	transfer := &fakeCheckoutTransfer{}
	c.Transfer = transfer
	task := checkoutTestTask()
	task.BaseGeneration, task.ImageDigest, task.ContentDigest = 3, strings.Repeat("b", 40), strings.Repeat("c", 64)

	c.process(context.Background(), task)

	if len(transfer.downloads) != 1 || transfer.downloads[0].BaseGeneration != 3 || transfer.downloads[0].ContentDigest != task.ContentDigest {
		t.Fatalf("downloads %+v", transfer.downloads)
	}
	if data, _ := os.ReadFile(c.Master(checkoutTestScope, 1)); string(data) != "head" {
		t.Fatal("the HEAD did not become this host's master")
	}
	if !host.ran("hdiutil", "attach", filepath.Join(c.dir(checkoutTestScope, 1), "next.sparseimage"), "-readonly") {
		t.Fatal("the restored master's tip is read from a read-only mount")
	}
	if meta, err := c.readMeta(checkoutTestScope, 1); err != nil || meta.Tip != checkoutTestCommit {
		t.Fatalf("meta %+v %v", meta, err)
	}

	c.process(context.Background(), task)
	if len(transfer.downloads) != 1 {
		t.Fatal("restored over an existing master")
	}
}

func TestCheckoutExportsAreReadWithoutFollowingLinks(t *testing.T) {
	c, _ := newCheckouts(t)
	outside := filepath.Join(t.TempDir(), "secret")
	_ = os.WriteFile(outside, []byte("host file"), 0600)
	for _, entry := range []string{"pack", "head"} {
		task := exportFrom(t, c, "job-"+entry, checkoutTestCommit, nil)
		_ = os.Remove(filepath.Join(task.Export, entry))
		if err := os.Symlink(outside, filepath.Join(task.Export, entry)); err != nil {
			t.Fatal(err)
		}
		if export, err := openCheckoutExport(task.Export); err == nil {
			export.Close()
			t.Fatalf("followed a %s link out of the export", entry)
		}
	}
	link := filepath.Join(t.TempDir(), "export")
	_ = os.Symlink(t.TempDir(), link)
	if _, err := openCheckoutExport(link); err == nil {
		t.Fatal("opened an export that is a link")
	}
}

func TestCheckoutFailedBuildKeepsThePreviousMaster(t *testing.T) {
	c, host := newCheckouts(t)
	c.process(context.Background(), exportFrom(t, c, "first", checkoutTestCommit, nil))
	before, _ := os.ReadFile(c.Master(checkoutTestScope, 1))
	host.fail = func(call checkoutCall) bool {
		return call.name == "git" && call.args[0] == "lfs" && call.args[1] == "checkout"
	}
	next := exportFrom(t, c, "next", checkoutTestOther, nil)
	next.Commit = checkoutTestOther
	host.reset()
	c.process(context.Background(), next)
	if !host.ran("git", "lfs", "checkout") {
		t.Fatal("the build never ran")
	}
	after, err := os.ReadFile(c.Master(checkoutTestScope, 1))
	if err != nil || string(after) != string(before) {
		t.Fatal("a failed build replaced the master")
	}
	if _, err := os.Stat(filepath.Join(c.dir(checkoutTestScope, 1), "next.sparseimage")); !os.IsNotExist(err) {
		t.Fatal("a failed build left its image behind")
	}
}

func TestCheckoutRecentCommitsExpire(t *testing.T) {
	c, host := newCheckouts(t)
	c.process(context.Background(), exportFrom(t, c, "first", checkoutTestCommit, nil))
	meta, _ := c.readMeta(checkoutTestScope, 1)
	old := strings.Repeat("e", 40)
	meta.Recent[old] = time.Now().Add(-15 * 24 * time.Hour)
	_ = c.writeMeta(checkoutTestScope, 1, meta)
	host.reset()
	c.process(context.Background(), exportFrom(t, c, "next", checkoutTestCommit, nil))
	if !host.ran("git", "remote", "set-url", "origin") || !host.ran("git", "update-ref", "-d", "refs/tuist/recent/"+old) {
		t.Fatal("a build keeps the remote canonical and expires old job commits")
	}
	if meta, _ = c.readMeta(checkoutTestScope, 1); !meta.Recent[old].IsZero() {
		t.Fatal("expired commit still recorded")
	}
}

func TestCheckoutClearDropsThePreviousScopesCopies(t *testing.T) {
	c, _ := newCheckouts(t)
	first := exportFrom(t, c, "first", checkoutTestCommit, nil)
	first.VolumeKey = strings.Repeat("d", 64)
	c.Track(first)
	c.process(context.Background(), first)

	cleared := exportFrom(t, c, "cleared", checkoutTestCommit, nil)
	cleared.VolumeKey, cleared.Scope = first.VolumeKey, strings.Repeat("e", 64)
	c.Track(cleared)
	deadline := time.Now().Add(5 * time.Second)
	for c.Master(first.Scope, 1) != "" && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if c.Master(first.Scope, 1) != "" {
		t.Fatal("a cleared volume's copy survived")
	}
	c.Track(cleared)
	c.process(context.Background(), cleared)
	if c.Master(cleared.Scope, 1) == "" {
		t.Fatal("the new scope has no copy")
	}
}

func TestCheckoutColdBuildsOnlyStartFromDefaultBranchCommits(t *testing.T) {
	c, host := newCheckouts(t)
	branch := exportFrom(t, c, "branch", checkoutTestCommit, nil)
	branch.DefaultBranchJob = false
	c.process(context.Background(), branch)
	if c.Master(checkoutTestScope, 1) != "" || host.ran("hdiutil", "create") {
		t.Fatal("a branch job started a master every later job would be handed")
	}

	moved := exportFrom(t, c, "moved", checkoutTestOther, nil)
	c.process(context.Background(), moved)
	if c.Master(checkoutTestScope, 1) != "" {
		t.Fatal("a default-branch job whose checkout is not its commit started a master")
	}
}

func TestCheckoutKeepsOnlyLFSObjectsTheCommitReferences(t *testing.T) {
	c, host := newCheckouts(t)
	used, unused := "used content", "unused content"
	host.lfs = []string{lfsOID(used)}
	c.process(context.Background(), exportFrom(t, c, "job", checkoutTestCommit, map[string]string{lfsOID(used): used, lfsOID(unused): unused}))
	if _, err := os.Stat(filepath.Join(lfsStore(c), lfsOID(used)[:2], lfsOID(used)[2:4], lfsOID(used))); err != nil {
		t.Fatal("the referenced LFS object was not kept")
	}
	if _, err := os.Stat(filepath.Join(lfsStore(c), lfsOID(unused)[:2], lfsOID(unused)[2:4], lfsOID(unused))); !os.IsNotExist(err) {
		t.Fatal("kept an LFS object no commit references")
	}
}

func TestCheckoutReservesRoomForLargeExportsAndRefusesOversizedOnes(t *testing.T) {
	c, _ := newCheckouts(t)
	var reserved uint64
	c.Room = func(_ context.Context, bytes uint64) (func(), error) {
		reserved = bytes
		return func() {}, nil
	}
	large := exportFrom(t, c, "large", checkoutTestCommit, nil)
	if err := os.Truncate(filepath.Join(large.Export, "pack"), 15_000_000_000); err != nil {
		t.Fatal(err)
	}
	c.process(context.Background(), large)
	if reserved < 30_000_000_000 {
		t.Fatalf("reserved %d for a 15 GB export", reserved)
	}

	oversized := exportFrom(t, c, "oversized", checkoutTestCommit, nil)
	if err := os.Truncate(filepath.Join(oversized.Export, "pack"), checkoutExportMax+1); err != nil {
		t.Fatal(err)
	}
	if export, err := openCheckoutExport(oversized.Export); err == nil {
		export.Close()
		t.Fatal("accepted an export larger than an image can hold")
	}
}

func TestCheckoutRestoreKeepsAgingThePublishersJobCommits(t *testing.T) {
	host := &fakeCheckoutHost{}
	c := &Checkouts{Root: t.TempDir(), Transfer: &fakeCheckoutTransfer{}, Run: func(ctx context.Context, dir string, env []string, name string, args ...string) ([]byte, error) {
		if name == "git" && args[0] == "for-each-ref" {
			return []byte(checkoutTestOther + "\n"), nil
		}
		return host.run(ctx, dir, env, name, args...)
	}}
	task := checkoutTestTask()
	task.BaseGeneration, task.ImageDigest, task.ContentDigest = 3, strings.Repeat("b", 40), strings.Repeat("c", 64)
	c.process(context.Background(), task)
	if meta, err := c.readMeta(checkoutTestScope, 1); err != nil || meta.Recent[checkoutTestOther].IsZero() {
		t.Fatalf("meta %+v %v", meta, err)
	}
}

func TestCheckoutHostWithoutGitDeniesCheckouts(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := checkoutRequest(t, root, pod)
	checkouts := &Checkouts{Root: filepath.Join(root, "checkouts")}
	c, _, _ := checkoutAgent(t, root, checkoutGrantJSON(0), checkouts)
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(filepath.Join(share, "checkout.request.response")); !strings.Contains(string(data), `"denied"`) {
		t.Fatal(string(data))
	}
}

func TestCheckoutTasksAreValidated(t *testing.T) {
	c, _ := newCheckouts(t)
	c.queue, c.ready = make(chan string, 1), true
	for name, mutate := range map[string]func(*checkoutTask){
		"other host":            func(t *checkoutTask) { t.CloneURL = "https://example.com/org/repo" },
		"option branch":         func(t *checkoutTask) { t.DefaultBranch = "--upload-pack=evil" },
		"dotted branch":         func(t *checkoutTask) { t.DefaultBranch = "a..b" },
		"short commit":          func(t *checkoutTask) { t.Commit = "abc" },
		"bad scope":             func(t *checkoutTask) { t.Scope = "../x" },
		"no use":                func(t *checkoutTask) { t.Use = "" },
		"export elsewhere":      func(t *checkoutTask) { t.Export = "/etc" },
		"restore without HEAD":  func(t *checkoutTask) { t.Export = "" },
		"HEAD without digests":  func(t *checkoutTask) { t.BaseGeneration = 2 },
		"negative base":         func(t *checkoutTask) { t.BaseGeneration = -1 },
		"negative generation":   func(t *checkoutTask) { t.Generation = -1 },
		"export outside folder": func(t *checkoutTask) { t.Export = filepath.Join(c.Root, "export") },
	} {
		task := checkoutTestTask()
		task.Export = c.Incoming("job")
		mutate(&task)
		if c.Enqueue(task) {
			t.Fatalf("%s accepted", name)
		}
	}
	first := exportFrom(t, c, "first", checkoutTestCommit, nil)
	second := exportFrom(t, c, "second", checkoutTestCommit, nil)
	if !c.Enqueue(first) || !c.Enqueue(second) {
		t.Fatal("repeated requests coalesce")
	}
	if len(c.queue) != 1 || c.pending[checkoutTestScope].Export != second.Export {
		t.Fatal("one queued build per volume, the newest")
	}
	if _, err := os.Stat(first.Export); !os.IsNotExist(err) {
		t.Fatal("a replaced export was kept")
	}
	restore := checkoutTestTask()
	restore.BaseGeneration, restore.ImageDigest, restore.ContentDigest = 1, strings.Repeat("b", 40), strings.Repeat("c", 64)
	if !c.Enqueue(restore) || c.pending[checkoutTestScope].Export != second.Export {
		t.Fatal("a restore never replaces a queued export")
	}
}

func TestCheckoutSeedClonesTheMasterAndRefusesOthers(t *testing.T) {
	c, _ := newCheckouts(t)
	c.process(context.Background(), exportFrom(t, c, "first", checkoutTestCommit, nil))
	slot := cachevolumes.Slot{Identity: cachevolumes.Identity{Scope: checkoutTestScope, Kind: cachevolumes.KindCheckout, Generation: 1}}
	dst := filepath.Join(t.TempDir(), "branch")
	if err := c.Seed(context.Background(), slot, dst); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(dst); string(data) != "image" {
		t.Fatal("seed did not clone the master")
	}
	slot.Generation = 2
	if err := c.Seed(context.Background(), slot, dst+"2"); err == nil {
		t.Fatal("seeded from another generation")
	}
	slot.Kind = ""
	if err := c.Seed(context.Background(), slot, dst+"3"); err == nil {
		t.Fatal("seeded a custom volume")
	}
}

func TestCheckoutEvictionSkipsMastersInUse(t *testing.T) {
	c, _ := newCheckouts(t)
	c.process(context.Background(), exportFrom(t, c, "first", checkoutTestCommit, nil))
	other := exportFrom(t, c, "other", checkoutTestCommit, nil)
	other.Scope = strings.Repeat("b", 64)
	c.process(context.Background(), other)
	old := time.Now().Add(-8 * 24 * time.Hour)
	_ = os.Chtimes(c.Master(checkoutTestScope, 1), old, old)

	c.setBusy(checkoutTestScope, true)
	c.Maintain()
	if c.Master(checkoutTestScope, 1) == "" {
		t.Fatal("evicted a master being built")
	}
	c.setBusy(checkoutTestScope, false)
	c.Maintain()
	if c.Master(checkoutTestScope, 1) != "" || c.Master(other.Scope, 1) == "" {
		t.Fatal("idle eviction removes only week-old masters")
	}
	if !c.Evict(func() bool { return false }) || c.Master(other.Scope, 1) != "" {
		t.Fatal("pressure eviction removes least recently used masters")
	}
}

func checkoutAgent(t *testing.T, root string, grant map[string]any, checkouts *Checkouts) (*CustomVolumes, *cachevolumes.Store, *[]map[string]any) {
	t.Helper()
	reports := &[]map[string]any{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var got map[string]any
		_ = json.NewDecoder(r.Body).Decode(&got)
		if r.URL.Path == "/report" {
			*reports = append(*reports, got)
			_ = json.NewEncoder(w).Encode(map[string]any{"action": "forget"})
			return
		}
		if r.URL.Path != "/checkout" || got["pod_name"] != "host-pod" || got["node_name"] != "host-node" || got["key"] != nil {
			t.Errorf("unexpected checkout request %s %v", r.URL.Path, got)
		}
		_ = json.NewEncoder(w).Encode(grant)
	}))
	t.Cleanup(server.Close)
	kube := fake.NewSimpleClientset()
	kube.PrependReactor("create", "serviceaccounts", func(ktesting.Action) (bool, runtime.Object, error) {
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{Token: "host-only"}}, nil
	})
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: root, SizeGB: 20, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }},
		Create: func(context.Context, string, int64) error { t.Fatal("checkout formatted an empty image"); return nil }, Seed: checkouts.Seed}
	if err := backend.Init(); err != nil {
		t.Fatal(err)
	}
	store, err := cachevolumes.Open(root, backend)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	return &CustomVolumes{Root: root, URL: server.URL, HTTP: server.Client(), Node: "host-node", Namespace: "runners", ServiceAccount: "cache-agent", Kube: kube, Store: store, Checkouts: checkouts}, store, reports
}

func checkoutGrantJSON(base int64) map[string]any {
	grant := map[string]any{
		"id": checkoutTestUse, "account_id": 1, "scope": checkoutTestScope, "uid": 501, "generation": 1, "can_publish": true,
		"clone_url": "https://github.com/org/repo", "default_branch": "main", "commit": checkoutTestCommit, "default_branch_job": true,
		"volume_key": strings.Repeat("d", 64),
	}
	if base > 0 {
		grant["base_generation"], grant["parent_id"] = base, "22222222-2222-4222-8222-222222222222"
		grant["image_digest"], grant["content_digest"] = strings.Repeat("b", 40), strings.Repeat("c", 64)
	}
	return grant
}

func checkoutRequest(t *testing.T, root string, pod *corev1.Pod) string {
	t.Helper()
	share := filepath.Join(root, "pods", string(pod.UID))
	if err := os.MkdirAll(share, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(share, "checkout.request"), []byte(`{"checkout":true,"uid":501,"key":"other"}`), 0600); err != nil {
		t.Fatal(err)
	}
	return share
}

func TestCheckoutMailboxRequestSeedsTheWorkspaceVolume(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := checkoutRequest(t, root, pod)
	checkouts, _ := newCheckouts(t)
	checkouts.process(context.Background(), exportFrom(t, checkouts, "first", checkoutTestCommit, nil))
	checkouts.queue, checkouts.ready = make(chan string, 1), true
	c, store, _ := checkoutAgent(t, root, checkoutGrantJSON(1), checkouts)
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(share, "checkout.request.response"))
	if err != nil {
		t.Fatal(err)
	}
	var response map[string]any
	_ = json.Unmarshal(data, &response)
	if response["id"] != checkoutTestUse || response["directory"] != checkoutTestScope || response["warm"] != true {
		t.Fatal(string(data))
	}
	if image, _ := os.ReadFile(filepath.Join(share, checkoutTestScope, "cache.sparseimage")); string(image) != "image" {
		t.Fatal("the guest's branch is not a clone of the master")
	}
	slots, _ := store.Snapshot()
	if len(slots) != 1 || slots[0].Kind != cachevolumes.KindCheckout || slots[0].CanPublish || slots[0].BaseGeneration != 0 || slots[0].ParentID != "" {
		t.Fatalf("journaled %+v", slots)
	}
	if len(checkouts.queue) != 0 {
		t.Fatal("a host with a master restores nothing")
	}
}

func TestCheckoutColdHostRestoresTheHeadAndBuildsFromTheExport(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := checkoutRequest(t, root, pod)
	checkouts := &Checkouts{Root: filepath.Join(root, "checkouts"), Run: (&fakeCheckoutHost{}).run}
	checkouts.queue, checkouts.ready = make(chan string, 2), true
	c, store, reports := checkoutAgent(t, root, checkoutGrantJSON(1), checkouts)
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(share, "checkout.request.response"))
	if !strings.Contains(string(data), `"cold"`) {
		t.Fatal(string(data))
	}
	if task := checkouts.pending[checkoutTestScope]; len(checkouts.queue) != 1 || task.Export != "" || task.BaseGeneration != 1 {
		t.Fatalf("a cold host with a HEAD restores it: %+v", task)
	}
	if slots, _ := store.Snapshot(); len(slots) != 0 {
		t.Fatalf("a cold checkout admitted a branch that cannot exist: %+v", slots)
	}
	if len(*reports) != 1 || (*reports)[0]["state"] != "deleted" || (*reports)[0]["id"] != checkoutTestUse {
		t.Fatalf("the cold use was not ended: %v", *reports)
	}

	// The job's export is taken out of the share once the pod is gone.
	export := filepath.Join(share, checkoutExportDir)
	_ = os.MkdirAll(export, 0755)
	_ = os.WriteFile(filepath.Join(export, "head"), []byte(checkoutTestCommit), 0644)
	c.collectCheckout(string(pod.UID))
	task := checkouts.pending[checkoutTestScope]
	if task.Export != checkouts.Incoming(string(pod.UID)) || task.Use != checkoutTestUse || task.BaseGeneration != 1 {
		t.Fatalf("the export did not replace the restore: %+v", task)
	}
	if _, err := os.Stat(filepath.Join(task.Export, "head")); err != nil {
		t.Fatal("the export was not moved out of the share")
	}
	c.collectCheckout(string(pod.UID))
	if len(checkouts.queue) != 1 {
		t.Fatal("a pod's export is collected once")
	}
}

func TestCheckoutExportsAreOnlyCollectedFromRealDirectoriesOfGrantedJobs(t *testing.T) {
	root := t.TempDir()
	checkouts := &Checkouts{Root: filepath.Join(root, "checkouts")}
	checkouts.queue, checkouts.ready = make(chan string, 2), true
	c := &CustomVolumes{Root: root, Checkouts: checkouts}
	share := filepath.Join(root, "pods", "pod-uid")
	_ = os.MkdirAll(filepath.Join(share, checkoutExportDir), 0755)
	c.collectCheckout("pod-uid")
	if len(checkouts.queue) != 0 {
		t.Fatal("collected an export without a grant")
	}
	_ = os.RemoveAll(filepath.Join(share, checkoutExportDir))
	_ = os.Symlink(t.TempDir(), filepath.Join(share, checkoutExportDir))
	c.rememberCheckout("pod-uid", exportFrom(t, checkouts, "unused", checkoutTestCommit, nil))
	c.collectCheckout("pod-uid")
	if len(checkouts.queue) != 0 {
		t.Fatal("collected a link out of the share")
	}
}

func TestCustomMailboxNeverAllocatesACheckoutIdentity(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := filepath.Join(root, "pods", string(pod.UID))
	_ = os.MkdirAll(share, 0755)
	_ = os.WriteFile(filepath.Join(share, "cache.request"), []byte(`{"key":"gradle","uid":501}`), 0600)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"id": checkoutTestUse, "account_id": 1, "scope": checkoutTestScope, "uid": 501, "kind": "checkout", "generation": 1})
	}))
	defer server.Close()
	kube := fake.NewSimpleClientset()
	kube.PrependReactor("create", "serviceaccounts", func(ktesting.Action) (bool, runtime.Object, error) {
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{Token: "host-only"}}, nil
	})
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: root, SizeGB: 20, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }},
		Create: func(_ context.Context, p string, _ int64) error { return os.WriteFile(p, nil, 0600) }}
	_ = backend.Init()
	store, _ := cachevolumes.Open(root, backend)
	defer store.Close()
	c := &CustomVolumes{Root: root, URL: server.URL, HTTP: server.Client(), Node: "host-node", Namespace: "runners", ServiceAccount: "cache-agent", Kube: kube, Store: store}
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	slots, _ := store.Snapshot()
	if len(slots) != 1 || slots[0].Kind != "" || slots[0].Generation != 0 {
		t.Fatalf("custom request journaled %+v", slots)
	}
}

func TestCheckoutGitLFSIsVerifiedBeforeUse(t *testing.T) {
	c, _ := newCheckouts(t)
	c.Download = func(context.Context) ([]byte, error) { return []byte("not the release"), nil }
	if err := c.ensureGitLFS(context.Background()); err == nil {
		t.Fatal("installed an unverified git-lfs")
	}
	if _, err := os.Stat(filepath.Join(c.Root, ".bin", "git-lfs")); !os.IsNotExist(err) {
		t.Fatal("left an unverified binary behind")
	}
	_ = os.MkdirAll(filepath.Join(c.Root, ".bin"), 0700)
	_ = os.WriteFile(filepath.Join(c.Root, ".bin", "git-lfs"), []byte("installed"), 0755)
	_ = os.WriteFile(filepath.Join(c.Root, ".bin", "git-lfs.sha256"), []byte(gitLFSSHA256), 0600)
	c.Download = func(context.Context) ([]byte, error) { t.Fatal("downloaded an installed git-lfs"); return nil, nil }
	if err := c.ensureGitLFS(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestCheckoutBuildRefusedForRoomIsRetriedByMaintain(t *testing.T) {
	c, _ := newCheckouts(t)
	c.ready, c.queue = true, make(chan string, checkoutQueue)
	full := true
	c.Room = func(context.Context, uint64) (func(), error) {
		if full {
			return nil, cachevolumes.ErrCapacity
		}
		return func() {}, nil
	}
	task := exportFrom(t, c, "job", checkoutTestCommit, nil)
	c.process(context.Background(), task)
	if c.Master(checkoutTestScope, 1) != "" || len(c.queue) != 0 {
		t.Fatal("a build without room ran or was queued straight away")
	}
	if _, err := os.Stat(task.Export); err != nil {
		t.Fatal("a waiting build lost its export")
	}

	full = false
	c.Maintain()
	if len(c.queue) != 1 {
		t.Fatal("maintain did not retry the refused build")
	}
	c.process(context.Background(), c.pending[<-c.queue])
	if c.Master(checkoutTestScope, 1) == "" {
		t.Fatal("the retried build made no master")
	}
	c.Maintain()
	if len(c.queue) != 0 {
		t.Fatal("a finished build was retried again")
	}
}

func TestCheckoutWaitingBuildsGiveUpAfterAWhile(t *testing.T) {
	c, _ := newCheckouts(t)
	c.ready, c.queue = true, make(chan string, checkoutQueue)
	c.Room = func(context.Context, uint64) (func(), error) { return nil, cachevolumes.ErrCapacity }
	task := exportFrom(t, c, "job", checkoutTestCommit, nil)
	task.Since = time.Now().Add(-2 * checkoutWaitFor)
	c.process(context.Background(), task)
	c.Maintain()
	if len(c.queue) != 0 {
		t.Fatal("kept retrying a build past its wait")
	}
	if _, err := os.Stat(task.Export); !os.IsNotExist(err) {
		t.Fatal("kept the export of a build it gave up on")
	}
}

func TestCheckoutNewerRequestReplacesAWaitingBuild(t *testing.T) {
	c, _ := newCheckouts(t)
	c.ready, c.queue = true, make(chan string, checkoutQueue)
	c.Room = func(context.Context, uint64) (func(), error) { return nil, cachevolumes.ErrCapacity }
	first := exportFrom(t, c, "first", checkoutTestCommit, nil)
	c.process(context.Background(), first)

	newer := exportFrom(t, c, "newer", checkoutTestOther, nil)
	c.Enqueue(newer)
	c.Maintain()
	if len(c.queue) != 1 || c.pending[checkoutTestScope].Export != newer.Export {
		t.Fatal("the waiting build was not replaced by the newer request")
	}
	if _, err := os.Stat(first.Export); !os.IsNotExist(err) {
		t.Fatal("kept the replaced export")
	}
}

func TestCheckoutEvictableCountsOnlyMastersNoBuildHolds(t *testing.T) {
	c, _ := newCheckouts(t)
	c.process(context.Background(), exportFrom(t, c, "first", checkoutTestCommit, nil))
	other := exportFrom(t, c, "other", checkoutTestCommit, nil)
	other.Scope = strings.Repeat("b", 64)
	c.process(context.Background(), other)
	size := func(string) (uint64, error) { return 3, nil }

	if got := c.Evictable(size); got != 6 {
		t.Fatalf("evictable %d, want both masters", got)
	}
	c.setBusy(other.Scope, true)
	if got := c.Evictable(size); got != 3 {
		t.Fatalf("evictable %d, want only the idle master", got)
	}
}
