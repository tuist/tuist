package main

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes/fake"
)

var checkoutScope = strings.Repeat("a", 64)

const checkoutUse = "11111111-1111-4111-8111-111111111111"
const checkoutCommit = "0123456789abcdef0123456789abcdef01234567"

func checkoutGrantJSON(base int64) map[string]any {
	grant := map[string]any{
		"id": checkoutUse, "account_id": 1, "scope": checkoutScope, "uid": 1000, "generation": 1, "can_publish": true,
		"clone_url": "https://github.com/org/repo", "default_branch": "main", "commit": checkoutCommit, "default_branch_job": true,
		"volume_key": strings.Repeat("d", 64),
	}
	if base > 0 {
		grant["base_generation"], grant["parent_id"] = base, "22222222-2222-4222-8222-222222222222"
		grant["image_digest"], grant["content_digest"] = strings.Repeat("b", 40), strings.Repeat("c", 64)
	}
	return grant
}

type checkoutServer struct {
	grant   map[string]any
	paths   []string
	reports []map[string]any
}

// checkoutAgent is an agent on node "node" serving pod "runner" at 10.0.0.5,
// against a server that grants grant.
func checkoutAgent(t *testing.T, grant map[string]any, ready bool) (*agent, *checkoutServer) {
	t.Helper()
	root := t.TempDir()
	store, err := cachevolumes.Open(root, testBackend{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	server := &checkoutServer{grant: grant}
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		server.paths = append(server.paths, r.URL.Path)
		switch r.URL.Path {
		case "/report":
			server.reports = append(server.reports, body)
			_ = json.NewEncoder(w).Encode(map[string]any{"action": "forget"})
		case "/checkout":
			if body["pod_name"] != "runner" || body["node_name"] != "node" || body["key"] != nil {
				t.Errorf("unexpected checkout request %v", body)
			}
			_ = json.NewEncoder(w).Encode(server.grant)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(upstream.Close)
	tokenPath := filepath.Join(root, "token")
	_ = os.WriteFile(tokenPath, []byte("agent-token"), 0600)
	fakeRun := func(context.Context, string, []string, string, ...string) ([]byte, error) { return nil, nil }
	checkouts := &cachevolumes.Checkouts{Root: filepath.Join(root, "checkouts"), Run: fakeRun, Images: &cachevolumes.Ext4CheckoutImages{Run: fakeRun}}
	if ready {
		if err := checkouts.Prepare(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "runner", Namespace: "runners", UID: types.UID("uid"), Labels: map[string]string{"tuist.dev/runner": "true"}}, Spec: corev1.PodSpec{NodeName: "node"}, Status: corev1.PodStatus{PodIP: "10.0.0.5", Phase: corev1.PodRunning}}
	return &agent{tokenPath: tokenPath, store: store, kube: fake.NewSimpleClientset(pod), namespace: "runners", node: "node", authorizeURL: upstream.URL + "/authorize", http: upstream.Client(), checkouts: checkouts, exports: make(chan struct{}, 2)}, server
}

func installMaster(t *testing.T, a *agent) {
	t.Helper()
	dir := filepath.Join(a.checkouts.Root, checkoutScope, "1")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "master.img"), []byte("master"), 0600); err != nil {
		t.Fatal(err)
	}
}

func requestCheckout(t *testing.T, a *agent, ip string) (int, map[string]any) {
	t.Helper()
	body, _ := json.Marshal(map[string]any{"pod_name": "runner", "pod_uid": "uid", "uid": 1000})
	req := httptest.NewRequest("POST", "/checkout", bytes.NewReader(body))
	req.RemoteAddr = ip + ":1234"
	w := httptest.NewRecorder()
	a.serve(w, req)
	var response map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &response)
	return w.Code, response
}

func sendExport(t *testing.T, a *agent, ip string, archive []byte) int {
	t.Helper()
	req := httptest.NewRequest("POST", "/checkout-export?pod_name=runner&pod_uid=uid", bytes.NewReader(archive))
	req.RemoteAddr = ip + ":1234"
	w := httptest.NewRecorder()
	a.serve(w, req)
	return w.Code
}

func checkoutArchive(t *testing.T) []byte {
	t.Helper()
	var buffer bytes.Buffer
	archive := tar.NewWriter(&buffer)
	for name, content := range map[string]string{"head": checkoutCommit + "\n", "pack": "PACK"} {
		_ = archive.WriteHeader(&tar.Header{Name: name, Mode: 0644, Size: int64(len(content)), Typeflag: tar.TypeReg})
		_, _ = archive.Write([]byte(content))
	}
	_ = archive.Close()
	return buffer.Bytes()
}

func TestCheckoutMountsACloneOfTheHostsMaster(t *testing.T) {
	a, _ := checkoutAgent(t, checkoutGrantJSON(1), true)
	installMaster(t, a)
	code, response := requestCheckout(t, a, "10.0.0.5")
	if code != 200 || response["id"] != checkoutUse || response["directory"] != checkoutScope || response["warm"] != true {
		t.Fatalf("%d %v", code, response)
	}
	slots, _ := a.store.Snapshot()
	if len(slots) != 1 || slots[0].Kind != cachevolumes.KindCheckout || slots[0].CanPublish || slots[0].BaseGeneration != 0 || slots[0].ParentID != "" || slots[0].Generation != 1 {
		t.Fatalf("journaled %+v", slots)
	}
	if a.checkouts.Queued() != 0 {
		t.Fatal("a host with a master restores nothing")
	}
}

func TestCheckoutIsOnlyGrantedToTheRunnerPodItself(t *testing.T) {
	a, server := checkoutAgent(t, checkoutGrantJSON(1), true)
	installMaster(t, a)
	if code, _ := requestCheckout(t, a, "10.0.0.6"); code != http.StatusForbidden || len(server.paths) != 0 {
		t.Fatalf("a foreign address got %d after %v", code, server.paths)
	}
}

func TestCheckoutColdHostRestoresTheHeadAndEndsTheUse(t *testing.T) {
	a, server := checkoutAgent(t, checkoutGrantJSON(1), true)
	_, response := requestCheckout(t, a, "10.0.0.5")
	if response["reason"] != "cold" {
		t.Fatal(response)
	}
	if task, ok := a.checkouts.Pending(checkoutScope); !ok || task.Export != "" || task.BaseGeneration != 1 || task.UID != 1000 {
		t.Fatalf("a cold host with a HEAD restores it: %+v", task)
	}
	if slots, _ := a.store.Snapshot(); len(slots) != 0 {
		t.Fatalf("a cold checkout admitted a branch that cannot exist: %+v", slots)
	}
	if len(server.reports) != 1 || server.reports[0]["state"] != "deleted" || server.reports[0]["id"] != checkoutUse {
		t.Fatalf("the cold use was not ended: %v", server.reports)
	}
}

func TestCheckoutHostWithoutGitDeniesCheckouts(t *testing.T) {
	a, server := checkoutAgent(t, checkoutGrantJSON(0), false)
	if _, response := requestCheckout(t, a, "10.0.0.5"); response["reason"] != "denied" || len(server.paths) != 0 {
		t.Fatalf("%v after %v", response, server.paths)
	}
}

func TestCheckoutExportIsTakenOnceFromTheGrantedPod(t *testing.T) {
	a, _ := checkoutAgent(t, checkoutGrantJSON(0), true)
	if code := sendExport(t, a, "10.0.0.5", checkoutArchive(t)); code != http.StatusConflict {
		t.Fatalf("an export without a grant got %d", code)
	}
	requestCheckout(t, a, "10.0.0.5")
	if code := sendExport(t, a, "10.0.0.6", checkoutArchive(t)); code != http.StatusForbidden {
		t.Fatalf("an export from another address got %d", code)
	}
	if code := sendExport(t, a, "10.0.0.5", checkoutArchive(t)); code != http.StatusAccepted {
		t.Fatalf("the granted export got %d", code)
	}
	task, ok := a.checkouts.Pending(checkoutScope)
	if !ok || task.Export != a.checkouts.Incoming("uid") || task.Use != checkoutUse || task.Commit != checkoutCommit {
		t.Fatalf("queued %+v", task)
	}
	if data, err := os.ReadFile(filepath.Join(task.Export, "head")); err != nil || strings.TrimSpace(string(data)) != checkoutCommit {
		t.Fatal("the export was not received")
	}
	if code := sendExport(t, a, "10.0.0.5", checkoutArchive(t)); code != http.StatusConflict {
		t.Fatalf("a second export got %d", code)
	}
}

func TestCheckoutExportsThatAreNotExportsAreRefused(t *testing.T) {
	a, _ := checkoutAgent(t, checkoutGrantJSON(0), true)
	requestCheckout(t, a, "10.0.0.5")
	if code := sendExport(t, a, "10.0.0.5", []byte("not a tar archive")); code != http.StatusBadRequest {
		t.Fatalf("got %d", code)
	}
	if _, ok := a.checkouts.Pending(checkoutScope); ok {
		t.Fatal("queued a build from an invalid export")
	}
}

func TestCheckoutGrantsOfGonePodsAreForgotten(t *testing.T) {
	var grants checkoutGrants
	grants.remember("live", cachevolumes.CheckoutTask{Scope: checkoutScope})
	grants.remember("gone", cachevolumes.CheckoutTask{Scope: checkoutScope})
	grants.forget(map[string]bool{"live": true})
	if _, ok := grants.take("gone"); ok {
		t.Fatal("kept a gone pod's grant")
	}
	if _, ok := grants.take("live"); !ok {
		t.Fatal("dropped a live pod's grant")
	}
}

func TestCheckoutBuildsAreHeldBackFromJobAdmission(t *testing.T) {
	root := t.TempDir()
	checkouts := &cachevolumes.Checkouts{Root: filepath.Join(root, "checkouts"), Images: &cachevolumes.Ext4CheckoutImages{}}
	free := uint64(100)
	space := &checkoutSpace{root: root, reserve: 40, checkouts: checkouts, freeBytes: func(string) (uint64, error) { return free, nil }}
	release, err := space.room(context.Background(), 50)
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := space.free(context.Background(), root); got != 50 {
		t.Fatalf("jobs see %d free while a build holds 50 of 100", got)
	}
	if _, err := space.room(context.Background(), 20); err != cachevolumes.ErrCapacity {
		t.Fatalf("a second build ate into the reserve: %v", err)
	}
	release()
	if got, _ := space.free(context.Background(), root); got != 100 {
		t.Fatalf("released room still held: %d", got)
	}
}

func TestCheckoutMastersMakeRoomForJobs(t *testing.T) {
	root := t.TempDir()
	checkouts := &cachevolumes.Checkouts{Root: filepath.Join(root, "checkouts"), Images: &cachevolumes.Ext4CheckoutImages{}}
	master := filepath.Join(checkouts.Root, checkoutScope, "1", "master.img")
	if err := os.MkdirAll(filepath.Dir(master), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(master, []byte("master"), 0600); err != nil {
		t.Fatal(err)
	}
	free := uint64(10)
	space := &checkoutSpace{root: root, reserve: 40, checkouts: checkouts, freeBytes: func(string) (uint64, error) {
		if _, err := os.Stat(master); os.IsNotExist(err) {
			return 100, nil
		}
		return free, nil
	}}
	if err := space.reclaim(context.Background(), 50); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(master); !os.IsNotExist(err) {
		t.Fatal("a job's admission did not evict the idle checkout master")
	}
}

func TestCheckoutRequestsHaveTheirOwnSlots(t *testing.T) {
	a, server := checkoutAgent(t, checkoutGrantJSON(1), true)
	a.requests = make(chan struct{}, 1)
	a.requests <- struct{}{}
	installMaster(t, a)
	if _, response := requestCheckout(t, a, "10.0.0.5"); response["id"] != checkoutUse {
		t.Fatalf("busy acquisitions held off a checkout: %v", response)
	}
	a.checkoutRequests = make(chan struct{}, 1)
	a.checkoutRequests <- struct{}{}
	server.paths = nil
	if _, response := requestCheckout(t, a, "10.0.0.5"); response["reason"] != "busy" || len(server.paths) != 0 {
		t.Fatalf("%v after %v", response, server.paths)
	}
}

func TestCheckoutExportWaitsForASlotWithoutLosingItsGrant(t *testing.T) {
	a, _ := checkoutAgent(t, checkoutGrantJSON(0), true)
	requestCheckout(t, a, "10.0.0.5")
	a.exports = make(chan struct{}, 1)
	a.exports <- struct{}{}
	if code := sendExport(t, a, "10.0.0.5", checkoutArchive(t)); code != http.StatusServiceUnavailable {
		t.Fatalf("a busy host answered %d", code)
	}
	if code := sendExport(t, a, "10.0.0.6", checkoutArchive(t)); code != http.StatusForbidden {
		t.Fatalf("another address answered %d before the slot check", code)
	}
	<-a.exports
	if code := sendExport(t, a, "10.0.0.5", checkoutArchive(t)); code != http.StatusAccepted {
		t.Fatalf("the grant did not survive a busy host: %d", code)
	}
}

func TestCheckoutExportsStayAboveTheJobReserve(t *testing.T) {
	a, _ := checkoutAgent(t, checkoutGrantJSON(0), true)
	free := uint64(100)
	a.space = &checkoutSpace{root: a.checkouts.Root, reserve: 98, checkouts: a.checkouts, freeBytes: func(string) (uint64, error) { return free, nil }}
	requestCheckout(t, a, "10.0.0.5")
	if code := sendExport(t, a, "10.0.0.5", checkoutArchive(t)); code != http.StatusInsufficientStorage {
		t.Fatalf("an export below the reserve got %d", code)
	}
	if _, err := os.Stat(a.checkouts.Incoming("uid")); !os.IsNotExist(err) {
		t.Fatal("kept an export there was no room for")
	}
	if got, _ := a.space.free(context.Background(), ""); got != free {
		t.Fatalf("a refused export still holds room: %d", got)
	}
}

func TestCheckoutExportsOnAHostAreCappedTogether(t *testing.T) {
	root := t.TempDir()
	space := &checkoutSpace{root: root, reserve: 0, freeBytes: func(string) (uint64, error) { return 1 << 50, nil }}
	waiting := filepath.Join(root, "waiting")
	if err := os.MkdirAll(waiting, 0700); err != nil {
		t.Fatal(err)
	}
	release, err := space.intake(waiting)(checkoutIncomingLimit - 10)
	if err != nil {
		t.Fatal(err)
	}
	release()
	if _, err := space.intake(filepath.Join(root, "next"))(11); err != cachevolumes.ErrCapacity {
		t.Fatalf("a second export went past the cap: %v", err)
	}
	if err := os.RemoveAll(waiting); err != nil {
		t.Fatal(err)
	}
	if _, err := space.intake(filepath.Join(root, "next"))(11); err != nil {
		t.Fatalf("a consumed export still counts: %v", err)
	}
}

func TestCheckoutMastersAreInUseWhileAJobClonesThem(t *testing.T) {
	a, _ := checkoutAgent(t, checkoutGrantJSON(1), true)
	installMaster(t, a)
	inUse := a.store.InUse
	if inUse(checkoutScope) {
		t.Fatal("a volume nobody clones is in use")
	}
	requestCheckout(t, a, "10.0.0.5")
	if !inUse(checkoutScope) || inUse(strings.Repeat("b", 64)) {
		t.Fatal("a mounted clone does not hold its master")
	}
}

func TestCheckoutsOnlyRunThePinnedGitLFS(t *testing.T) {
	for out, ok := range map[string]bool{
		"git-lfs/3.8.0 (GitHub; linux amd64; go 1.24.4)\n": true,
		"git-lfs/3.3.0 (GitHub; linux amd64; go 1.19.8)\n": false,
		"git-lfs/3.8.01 (GitHub; linux amd64)\n":           false,
	} {
		err := pinnedGitLFS(func(context.Context) ([]byte, error) { return []byte(out), nil })(context.Background())
		if (err == nil) != ok {
			t.Errorf("%q: %v", out, err)
		}
	}
	missing := pinnedGitLFS(func(context.Context) ([]byte, error) { return nil, os.ErrNotExist })
	if missing(context.Background()) == nil {
		t.Error("a host without git-lfs serves checkouts")
	}
}

func TestCheckoutExportsDisplaceBuildsWaitingForRoom(t *testing.T) {
	a, _ := checkoutAgent(t, checkoutGrantJSON(0), true)
	a.checkouts.Room = func(context.Context, uint64) (func(), error) { return nil, cachevolumes.ErrCapacity }
	space := &checkoutSpace{root: a.checkouts.Root, checkouts: a.checkouts, freeBytes: func(string) (uint64, error) { return 1 << 50, nil }}
	waiting := a.checkouts.Incoming("waiting")
	if err := os.MkdirAll(waiting, 0700); err != nil {
		t.Fatal(err)
	}
	for name, content := range map[string]string{"head": checkoutCommit, "pack": "PACK"} {
		if err := os.WriteFile(filepath.Join(waiting, name), []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
	}
	release, err := space.intake(waiting)(checkoutIncomingLimit)
	if err != nil {
		t.Fatal(err)
	}
	release()
	task := cachevolumes.CheckoutTask{Scope: checkoutScope, Generation: 1, CloneURL: "https://github.com/org/repo", DefaultBranch: "main", Commit: checkoutCommit, DefaultBranchJob: true, Use: checkoutUse, Export: waiting}
	a.checkouts.Process(context.Background(), task)
	if _, err := os.Stat(waiting); err != nil {
		t.Fatal("the build refused for room did not keep its export")
	}
	if _, err := space.intake(a.checkouts.Incoming("next"))(10); err != nil {
		t.Fatalf("a waiting build blocked a newer export: %v", err)
	}
	if _, err := os.Stat(waiting); !os.IsNotExist(err) {
		t.Fatal("the displaced export was kept")
	}
}
