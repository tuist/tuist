package podagent

import (
	"context"
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
}

func (f *fakeCheckoutHost) run(_ context.Context, dir string, env []string, name string, args ...string) ([]byte, error) {
	call := checkoutCall{dir: dir, env: env, name: name, args: args}
	f.mu.Lock()
	f.calls = append(f.calls, call)
	fail := f.fail
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
	case name == "git" && args[0] == "rev-parse":
		return []byte(checkoutTestCommit + "\n"), nil
	}
	return nil, nil
}

func (f *fakeCheckoutHost) commands() []checkoutCall {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]checkoutCall(nil), f.calls...)
}

func (f *fakeCheckoutHost) ran(name string, args ...string) bool {
	for _, call := range f.commands() {
		if call.name == name && len(call.args) >= len(args) && strings.Join(call.args[:len(args)], " ") == strings.Join(args, " ") {
			return true
		}
	}
	return false
}

func newCheckouts(t *testing.T) (*Checkouts, *fakeCheckoutHost) {
	t.Helper()
	host := &fakeCheckoutHost{}
	return &Checkouts{Root: t.TempDir(), Run: host.run}, host
}

func checkoutTestTask() checkoutTask {
	return checkoutTask{
		Scope: checkoutTestScope, Generation: 1, CloneURL: "https://github.com/org/repo", DefaultBranch: "main",
		Commit: checkoutTestCommit, Token: "ghs_secret", TokenExpiresAt: time.Now().Add(time.Hour),
	}
}

func TestCheckoutColdBuildCreatesTheMasterFromGitHub(t *testing.T) {
	c, host := newCheckouts(t)
	c.process(context.Background(), checkoutTestTask())

	master := c.Master(checkoutTestScope, 1)
	if master == "" {
		t.Fatal("no master after a cold build")
	}
	if !host.ran("hdiutil", "create") || host.ran("cp") {
		t.Fatal("a cold build formats a new image")
	}
	for _, want := range [][]string{
		{"remote", "add", "origin", "https://github.com/org/repo"},
		{"config", "core.checkStat", "minimal"},
		{"-c", "protocol.version=2", "fetch", "--prune", "--no-tags", "--quiet", "origin", "+refs/heads/*:refs/remotes/origin/*", "+refs/tags/*:refs/tags/*"},
		{"-c", "protocol.version=2", "fetch", "--no-tags", "--quiet", "origin", "+" + checkoutTestCommit + ":refs/tuist/recent/" + checkoutTestCommit},
		{"checkout", "-q", "--detach", "--force", "refs/remotes/origin/main"},
		{"lfs", "fetch", "origin", "refs/remotes/origin/main", "refs/tuist/recent/" + checkoutTestCommit},
		{"lfs", "checkout"},
	} {
		if !host.ran("git", want...) {
			t.Fatalf("missing git %v", want)
		}
	}
	exclude, err := os.ReadFile(filepath.Join(c.dir(checkoutTestScope, 1), "next.mnt", ".git", "info", "exclude"))
	if err != nil || !strings.Contains(string(exclude), "/.fseventsd/") {
		t.Fatalf("exclude %q %v", exclude, err)
	}
	meta, err := c.readMeta(checkoutTestScope, 1)
	if err != nil || meta.Tip != checkoutTestCommit || meta.Recent[checkoutTestCommit].IsZero() {
		t.Fatalf("meta %+v %v", meta, err)
	}
}

func TestCheckoutTokenReachesGitOnlyThroughTheEnvironment(t *testing.T) {
	c, host := newCheckouts(t)
	c.process(context.Background(), checkoutTestTask())
	authorized := false
	for _, call := range host.commands() {
		for _, arg := range call.args {
			if strings.Contains(arg, "ghs_secret") || strings.Contains(arg, "x-access-token") {
				t.Fatalf("token in argv: %v", call.args)
			}
		}
		if call.name != "git" {
			if len(call.env) != 0 {
				t.Fatalf("%s got an environment", call.name)
			}
			continue
		}
		for _, variable := range call.env {
			if strings.HasPrefix(variable, "GIT_CONFIG_VALUE_0=AUTHORIZATION: basic ") {
				authorized = true
			}
		}
	}
	if !authorized {
		t.Fatal("git never got the extra header")
	}
	config, _ := os.ReadFile(filepath.Join(c.dir(checkoutTestScope, 1), "next.mnt", ".git", "config"))
	if strings.Contains(string(config), "ghs_secret") {
		t.Fatal("token persisted in the repository")
	}
}

func TestCheckoutRefreshClonesTheMasterAndExpiresOldCommits(t *testing.T) {
	c, host := newCheckouts(t)
	c.process(context.Background(), checkoutTestTask())
	meta, _ := c.readMeta(checkoutTestScope, 1)
	old := "fedcba9876543210fedcba9876543210fedcba98"
	meta.Recent[old] = time.Now().Add(-15 * 24 * time.Hour)
	meta.RefreshedAt = time.Now().Add(-time.Hour)
	if err := c.writeMeta(checkoutTestScope, 1, meta); err != nil {
		t.Fatal(err)
	}
	host.calls = nil

	c.process(context.Background(), checkoutTestTask())

	if host.ran("hdiutil", "create") || !host.ran("cp", "-c", c.masterPath(checkoutTestScope, 1)) {
		t.Fatal("a refresh clones the current master")
	}
	if !host.ran("git", "remote", "set-url", "origin") || !host.ran("git", "update-ref", "-d", "refs/tuist/recent/"+old) {
		t.Fatal("refresh keeps the remote canonical and expires old job commits")
	}
	meta, _ = c.readMeta(checkoutTestScope, 1)
	if _, ok := meta.Recent[old]; ok {
		t.Fatal("expired commit still recorded")
	}
}

func TestCheckoutRebuildsAStaleMasterFromScratch(t *testing.T) {
	c, host := newCheckouts(t)
	c.process(context.Background(), checkoutTestTask())
	meta, _ := c.readMeta(checkoutTestScope, 1)
	meta.BuiltAt = time.Now().Add(-31 * 24 * time.Hour)
	_ = c.writeMeta(checkoutTestScope, 1, meta)
	host.calls = nil
	c.process(context.Background(), checkoutTestTask())
	if !host.ran("hdiutil", "create") {
		t.Fatal("a month-old master is rebuilt, so history removed upstream leaves it")
	}
}

func TestCheckoutFailedBuildKeepsThePreviousMaster(t *testing.T) {
	c, host := newCheckouts(t)
	c.process(context.Background(), checkoutTestTask())
	before, _ := os.ReadFile(c.Master(checkoutTestScope, 1))
	host.fail = func(call checkoutCall) bool { return call.name == "git" && call.args[0] == "lfs" }
	refresh := checkoutTestTask()
	refresh.Commit = "fedcba9876543210fedcba9876543210fedcba98"
	host.calls = nil
	c.process(context.Background(), refresh)
	if !host.ran("git", "lfs") {
		t.Fatal("the refresh never ran")
	}
	after, err := os.ReadFile(c.Master(checkoutTestScope, 1))
	if err != nil || string(after) != string(before) {
		t.Fatal("a failed refresh replaced the master")
	}
	if _, err := os.Stat(filepath.Join(c.dir(checkoutTestScope, 1), "next.sparseimage")); !os.IsNotExist(err) {
		t.Fatal("a failed refresh left its image behind")
	}
}

func TestCheckoutSkipsTokensAboutToExpire(t *testing.T) {
	c, host := newCheckouts(t)
	task := checkoutTestTask()
	task.TokenExpiresAt = time.Now().Add(time.Minute)
	c.process(context.Background(), task)
	if len(host.commands()) != 0 {
		t.Fatal("built with an expiring token")
	}
}

func TestCheckoutClearDropsOlderGenerations(t *testing.T) {
	c, _ := newCheckouts(t)
	c.process(context.Background(), checkoutTestTask())
	task := checkoutTestTask()
	task.Generation = 2
	c.process(context.Background(), task)
	if c.Master(checkoutTestScope, 1) != "" || c.Master(checkoutTestScope, 2) == "" {
		t.Fatal("a cleared generation's master survived")
	}
}

func TestCheckoutTasksAreValidated(t *testing.T) {
	c, _ := newCheckouts(t)
	c.queue, c.ready = make(chan string, 1), true
	for name, mutate := range map[string]func(*checkoutTask){
		"other host":      func(t *checkoutTask) { t.CloneURL = "https://example.com/org/repo" },
		"option branch":   func(t *checkoutTask) { t.DefaultBranch = "--upload-pack=evil" },
		"dotted branch":   func(t *checkoutTask) { t.DefaultBranch = "a..b" },
		"short commit":    func(t *checkoutTask) { t.Commit = "abc" },
		"no token":        func(t *checkoutTask) { t.Token = "" },
		"multiline token": func(t *checkoutTask) { t.Token = "a\nb" },
		"bad scope":       func(t *checkoutTask) { t.Scope = "../x" },
	} {
		task := checkoutTestTask()
		mutate(&task)
		if c.Enqueue(task) {
			t.Fatalf("%s accepted", name)
		}
	}
	if !c.Enqueue(checkoutTestTask()) || !c.Enqueue(checkoutTestTask()) {
		t.Fatal("repeated requests coalesce")
	}
	if len(c.queue) != 1 {
		t.Fatal("one queued build per volume")
	}
}

func TestCheckoutSeedClonesTheMasterAndRefusesOthers(t *testing.T) {
	c, _ := newCheckouts(t)
	c.process(context.Background(), checkoutTestTask())
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
	c.process(context.Background(), checkoutTestTask())
	other := checkoutTestTask()
	other.Scope = strings.Repeat("b", 64)
	c.process(context.Background(), other)
	old := time.Now().Add(-8 * 24 * time.Hour)
	_ = os.Chtimes(c.Master(checkoutTestScope, 1), old, old)

	c.setBusy(checkoutTestScope, true)
	c.Maintain()
	if c.Master(checkoutTestScope, 1) == "" {
		t.Fatal("evicted a master being refreshed")
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

func TestCheckoutMailboxRequestSeedsTheWorkspaceVolume(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := filepath.Join(root, "pods", string(pod.UID))
	if err := os.MkdirAll(share, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(share, "checkout.request"), []byte(`{"checkout":true,"uid":501,"key":"other"}`), 0600); err != nil {
		t.Fatal(err)
	}
	id := "11111111-1111-4111-8111-111111111111"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var got map[string]any
		_ = json.NewDecoder(r.Body).Decode(&got)
		if r.URL.Path != "/checkout" || got["pod_name"] != "host-pod" || got["node_name"] != "host-node" || got["key"] != nil {
			t.Errorf("unexpected checkout request %s %v", r.URL.Path, got)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id": id, "account_id": 1, "scope": checkoutTestScope, "uid": 501, "generation": 1, "can_publish": true,
			"clone_url": "https://github.com/org/repo", "default_branch": "main", "commit": checkoutTestCommit,
			"token": "ghs_secret", "token_expires_at": time.Now().Add(time.Hour),
		})
	}))
	defer server.Close()
	kube := fake.NewSimpleClientset()
	kube.PrependReactor("create", "serviceaccounts", func(ktesting.Action) (bool, runtime.Object, error) {
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{Token: "host-only"}}, nil
	})
	checkouts, _ := newCheckouts(t)
	checkouts.process(context.Background(), checkoutTestTask())
	checkouts.queue, checkouts.ready = make(chan string, 1), true
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: root, SizeGB: 20, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }},
		Create: func(context.Context, string, int64) error { t.Fatal("checkout formatted an empty image"); return nil }, Seed: checkouts.Seed}
	if err := backend.Init(); err != nil {
		t.Fatal(err)
	}
	store, err := cachevolumes.Open(root, backend)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	c := &CustomVolumes{Root: root, URL: server.URL, HTTP: server.Client(), Node: "host-node", Namespace: "runners", ServiceAccount: "cache-agent", Kube: kube, Store: store, Checkouts: checkouts}
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(share, "checkout.request.response"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "ghs_secret") {
		t.Fatal("token reached the guest")
	}
	var response map[string]any
	_ = json.Unmarshal(data, &response)
	if response["id"] != id || response["directory"] != checkoutTestScope || response["warm"] != true {
		t.Fatal(string(data))
	}
	if image, _ := os.ReadFile(filepath.Join(share, checkoutTestScope, "cache.sparseimage")); string(image) != "image" {
		t.Fatal("the guest's branch is not a clone of the master")
	}
	slots, _ := store.Snapshot()
	if len(slots) != 1 || slots[0].Kind != cachevolumes.KindCheckout || slots[0].CanPublish {
		t.Fatalf("journaled %+v", slots)
	}
	if len(checkouts.queue) != 1 {
		t.Fatal("serving a checkout queues its refresh")
	}
}

func TestCustomMailboxNeverAllocatesACheckoutIdentity(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := filepath.Join(root, "pods", string(pod.UID))
	_ = os.MkdirAll(share, 0755)
	_ = os.WriteFile(filepath.Join(share, "cache.request"), []byte(`{"key":"gradle","uid":501}`), 0600)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"id": "11111111-1111-4111-8111-111111111111", "account_id": 1, "scope": checkoutTestScope, "uid": 501, "kind": "checkout", "generation": 1})
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

func TestCheckoutRefreshesAreThrottledUnlessTheJobCommitIsNew(t *testing.T) {
	c, host := newCheckouts(t)
	c.process(context.Background(), checkoutTestTask())
	host.calls = nil
	c.process(context.Background(), checkoutTestTask())
	if len(host.commands()) != 0 {
		t.Fatal("refreshed a volume that just refreshed with the same commit")
	}
	task := checkoutTestTask()
	task.Commit = "fedcba9876543210fedcba9876543210fedcba98"
	c.process(context.Background(), task)
	if !host.ran("git", "-c", "protocol.version=2", "fetch", "--no-tags", "--quiet", "origin", "+"+task.Commit+":refs/tuist/recent/"+task.Commit) {
		t.Fatal("a new job commit must still be fetched")
	}
}
