package podagent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

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
const checkoutTestUse = "11111111-1111-4111-8111-111111111111"

// fakeCheckoutRun stands in for hdiutil, cp and git, creating the files the
// real tools would.
func fakeCheckoutRun(_ context.Context, dir string, _ []string, name string, args ...string) ([]byte, error) {
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
		return []byte(strings.Repeat("9", 40) + "\n"), nil
	}
	return nil, nil
}

// preparedCheckouts accepts requests without running a build worker.
func preparedCheckouts(t *testing.T, root string) *cachevolumes.Checkouts {
	t.Helper()
	c := &cachevolumes.Checkouts{Root: root, Run: fakeCheckoutRun, Images: &cachevolumes.APFSCheckoutImages{Run: fakeCheckoutRun}}
	if err := c.Prepare(context.Background()); err != nil {
		t.Fatal(err)
	}
	return c
}

// exportFrom writes a finished job's export into the incoming directory.
func exportFrom(t *testing.T, c *cachevolumes.Checkouts, name, head string, _ map[string]string) cachevolumes.CheckoutTask {
	t.Helper()
	dir := c.Incoming(name)
	if err := os.MkdirAll(filepath.Join(dir, "lfs"), 0755); err != nil {
		t.Fatal(err)
	}
	for file, content := range map[string]string{"head": head + "\n", "pack": "PACK"} {
		if err := os.WriteFile(filepath.Join(dir, file), []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	return cachevolumes.CheckoutTask{
		Scope: checkoutTestScope, Generation: 1, CloneURL: "https://github.com/org/repo", DefaultBranch: "main",
		Commit: checkoutTestCommit, DefaultBranchJob: true, Use: checkoutTestUse, Export: dir,
	}
}

func TestCheckoutHostWithoutGitDeniesCheckouts(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := checkoutRequest(t, root, pod)
	checkouts := &cachevolumes.Checkouts{Root: filepath.Join(root, "checkouts"), Images: &cachevolumes.APFSCheckoutImages{}}
	c, _, _ := checkoutAgent(t, root, checkoutGrantJSON(0), checkouts)
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(filepath.Join(share, "checkout.request.response")); !strings.Contains(string(data), `"denied"`) {
		t.Fatal(string(data))
	}
}

func checkoutAgent(t *testing.T, root string, grant map[string]any, checkouts *cachevolumes.Checkouts) (*CustomVolumes, *cachevolumes.Store, *[]map[string]any) {
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
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: root, SizeGB: 20, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }, Seed: checkouts.Seed},
		Create: func(context.Context, string, int64) error { t.Fatal("checkout formatted an empty image"); return nil }}
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
		"may_start_master": true, "volume_key": strings.Repeat("d", 64),
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
	checkouts := preparedCheckouts(t, t.TempDir())
	checkouts.Process(context.Background(), exportFrom(t, checkouts, "first", checkoutTestCommit, nil))
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
	if checkouts.Queued() != 0 {
		t.Fatal("a host with a master restores nothing")
	}
}

func TestCheckoutColdHostRestoresTheHeadAndBuildsFromTheExport(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := checkoutRequest(t, root, pod)
	checkouts := preparedCheckouts(t, filepath.Join(root, "checkouts"))
	c, store, reports := checkoutAgent(t, root, checkoutGrantJSON(1), checkouts)
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(share, "checkout.request.response"))
	if !strings.Contains(string(data), `"cold"`) {
		t.Fatal(string(data))
	}
	if task, _ := checkouts.Pending(checkoutTestScope); checkouts.Queued() != 1 || task.Export != "" || task.BaseGeneration != 1 {
		t.Fatalf("a cold host with a HEAD restores it: %+v", task)
	}
	if slots, _ := store.Snapshot(); len(slots) != 0 {
		t.Fatalf("a cold checkout admitted a branch that cannot exist: %+v", slots)
	}
	if len(*reports) != 1 || (*reports)[0]["state"] != "deleted" || (*reports)[0]["id"] != checkoutTestUse {
		t.Fatalf("the cold use was not ended: %v", *reports)
	}

	// The job's export is taken out of the share once the pod is gone.
	export := filepath.Join(share, cachevolumes.CheckoutExportDir)
	_ = os.MkdirAll(export, 0755)
	_ = os.WriteFile(filepath.Join(export, "head"), []byte(checkoutTestCommit), 0644)
	c.collectCheckout(string(pod.UID))
	task, _ := checkouts.Pending(checkoutTestScope)
	if task.Export != checkouts.Incoming(string(pod.UID)) || task.Use != checkoutTestUse || task.BaseGeneration != 1 || !task.MayStartMaster {
		t.Fatalf("the export did not replace the restore: %+v", task)
	}
	if _, err := os.Stat(filepath.Join(task.Export, "head")); err != nil {
		t.Fatal("the export was not moved out of the share")
	}
	c.collectCheckout(string(pod.UID))
	if checkouts.Queued() != 1 {
		t.Fatal("a pod's export is collected once")
	}
}

func TestCheckoutExportsAreOnlyCollectedFromRealDirectoriesOfGrantedJobs(t *testing.T) {
	root := t.TempDir()
	checkouts := preparedCheckouts(t, filepath.Join(root, "checkouts"))
	c := &CustomVolumes{Root: root, Checkouts: checkouts}
	share := filepath.Join(root, "pods", "pod-uid")
	_ = os.MkdirAll(filepath.Join(share, cachevolumes.CheckoutExportDir), 0755)
	c.collectCheckout("pod-uid")
	if checkouts.Queued() != 0 {
		t.Fatal("collected an export without a grant")
	}
	_ = os.RemoveAll(filepath.Join(share, cachevolumes.CheckoutExportDir))
	_ = os.Symlink(t.TempDir(), filepath.Join(share, cachevolumes.CheckoutExportDir))
	c.rememberCheckout("pod-uid", exportFrom(t, checkouts, "unused", checkoutTestCommit, nil))
	c.collectCheckout("pod-uid")
	if checkouts.Queued() != 0 {
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
	root := t.TempDir()
	if err := GitLFS(root, func(context.Context) ([]byte, error) { return []byte("not the release"), nil })(context.Background()); err == nil {
		t.Fatal("installed an unverified git-lfs")
	}
	if _, err := os.Stat(filepath.Join(root, ".bin", "git-lfs")); !os.IsNotExist(err) {
		t.Fatal("left an unverified binary behind")
	}
	_ = os.MkdirAll(filepath.Join(root, ".bin"), 0700)
	_ = os.WriteFile(filepath.Join(root, ".bin", "git-lfs"), []byte("installed"), 0755)
	_ = os.WriteFile(filepath.Join(root, ".bin", "git-lfs.sha256"), []byte(gitLFSSHA256), 0600)
	download := func(context.Context) ([]byte, error) { t.Fatal("downloaded an installed git-lfs"); return nil, nil }
	if err := GitLFS(root, download)(context.Background()); err != nil {
		t.Fatal(err)
	}
}
