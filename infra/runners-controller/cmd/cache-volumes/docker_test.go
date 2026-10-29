package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes/fake"
)

const dockerUse = "33333333-3333-4333-8333-333333333333"

type dockerServer struct {
	status  int
	seen    int
	bodies  map[string]map[string]any
	reports []map[string]any
}

// dockerAgent is an agent on node "node" serving pod "runner" at 10.0.0.5,
// against a server that answers /docker with status.
func dockerAgent(t *testing.T, status int) (*agent, *dockerServer) {
	t.Helper()
	root := t.TempDir()
	store, err := cachevolumes.Open(root, testBackend{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	server := &dockerServer{status: status, seen: http.StatusNoContent, bodies: map[string]map[string]any{}}
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		server.bodies[r.URL.Path] = body
		switch r.URL.Path {
		case "/docker":
			if server.status != http.StatusOK {
				w.WriteHeader(server.status)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"id": dockerUse, "account_id": 1, "scope": strings.Repeat("e", 64), "uid": 0, "can_publish": true, "volume_bytes": cachevolumes.DockerVolumeBytes})
		case "/docker-seen":
			w.WriteHeader(server.seen)
		case "/report":
			server.reports = append(server.reports, body)
			_ = json.NewEncoder(w).Encode(map[string]any{"action": "hold"})
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(upstream.Close)
	tokenPath := filepath.Join(root, "token")
	_ = os.WriteFile(tokenPath, []byte("agent-token"), 0600)
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "runner", Namespace: "runners", UID: types.UID("uid"), Labels: map[string]string{"tuist.dev/runner": "true"}}, Spec: corev1.PodSpec{NodeName: "node"}, Status: corev1.PodStatus{PodIP: "10.0.0.5", Phase: corev1.PodRunning}}
	return &agent{tokenPath: tokenPath, store: store, root: root, kube: fake.NewSimpleClientset(pod), namespace: "runners", node: "node", authorizeURL: upstream.URL + "/authorize", http: upstream.Client()}, server
}

func requestDocker(t *testing.T, a *agent, path, ip string) (int, map[string]any) {
	t.Helper()
	body, _ := json.Marshal(map[string]any{"pod_name": "runner", "pod_uid": "uid"})
	req := httptest.NewRequest("POST", path, bytes.NewReader(body))
	req.RemoteAddr = ip + ":1234"
	w := httptest.NewRecorder()
	a.serve(w, req)
	var response map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &response)
	return w.Code, response
}

func TestDockerGrantsTheRootDaemonsDataRoot(t *testing.T) {
	a, server := dockerAgent(t, http.StatusOK)
	code, response := requestDocker(t, a, "/docker", "10.0.0.5")
	if code != http.StatusOK || response["id"] != dockerUse || response["directory"] != strings.Repeat("e", 64) {
		t.Fatalf("%d %v", code, response)
	}
	asked := server.bodies["/docker"]
	if asked["uid"] != float64(0) || asked["architecture"] != "amd64" || asked["max_volume_bytes"] != float64(cachevolumes.DockerVolumeBytes) || asked["node_name"] != "node" {
		t.Fatalf("server asked with %v", asked)
	}
	slots, err := a.store.Snapshot()
	if err != nil || len(slots) != 1 || slots[0].Kind != cachevolumes.KindDocker || slots[0].State != "active" {
		t.Fatalf("journal %v, %v", slots, err)
	}
}

func TestDockerUnseenRepositoryGetsNoBranch(t *testing.T) {
	a, _ := dockerAgent(t, http.StatusNotFound)
	code, response := requestDocker(t, a, "/docker", "10.0.0.5")
	if code != http.StatusOK || response["reason"] != "unseen" {
		t.Fatalf("%d %v", code, response)
	}
	if slots, _ := a.store.Snapshot(); len(slots) != 0 {
		t.Fatalf("journaled %v", slots)
	}
}

func TestDockerDeniedRepositoryGetsNoBranch(t *testing.T) {
	a, _ := dockerAgent(t, http.StatusForbidden)
	if _, response := requestDocker(t, a, "/docker", "10.0.0.5"); response["reason"] != "denied" {
		t.Fatalf("%v", response)
	}
}

func TestDockerRequestsComeFromTheirOwnPod(t *testing.T) {
	a, server := dockerAgent(t, http.StatusOK)
	for _, path := range []string{"/docker", "/docker-seen"} {
		if code, _ := requestDocker(t, a, path, "10.0.0.9"); code != http.StatusForbidden {
			t.Fatalf("%s from another address answered %d", path, code)
		}
	}
	if len(server.bodies) != 0 {
		t.Fatalf("forwarded %v", server.bodies)
	}
}

func TestDockerSeenIsForwarded(t *testing.T) {
	a, server := dockerAgent(t, http.StatusOK)
	if code, _ := requestDocker(t, a, "/docker-seen", "10.0.0.5"); code != http.StatusNoContent {
		t.Fatalf("seen answered %d", code)
	}
	if body := server.bodies["/docker-seen"]; body["pod_uid"] != "uid" || body["uid"] != float64(0) {
		t.Fatalf("server told %v", body)
	}
	server.seen = http.StatusForbidden
	if code, _ := requestDocker(t, a, "/docker-seen", "10.0.0.5"); code != http.StatusForbidden {
		t.Fatalf("refused seen answered %d", code)
	}
}

func TestDockerReportCarriesTheFinishedInventory(t *testing.T) {
	a, server := dockerAgent(t, http.StatusOK)
	requestDocker(t, a, "/docker", "10.0.0.5")
	slots, _ := a.store.Snapshot()
	report := cachevolumes.DockerReport{Clean: true, Changed: true, Reset: true, BuildCacheBytes: 7, Images: []cachevolumes.DockerImage{{ID: "sha256:" + strings.Repeat("a", 64), References: []string{"postgres:16"}, SizeBytes: 9}}}
	data, _ := json.Marshal(report)
	if err := os.WriteFile(filepath.Join(a.root, "pods", "uid", slots[0].Scope, cachevolumes.DockerReportName), data, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := a.report(slots[0], false); err != nil {
		t.Fatal(err)
	}
	if _, err := a.report(slots[0], true); err != nil {
		t.Fatal(err)
	}
	if _, running := server.reports[0]["docker"]; running {
		t.Fatal("reported an inventory while the job ran")
	}
	inventory, ok := server.reports[1]["docker"].(map[string]any)
	if !ok || inventory["build_cache_bytes"] != float64(7) || inventory["reset"] != true || len(inventory["images"].([]any)) != 1 {
		t.Fatalf("reported %v", server.reports[1])
	}
}

func TestDockerMergeOffersTheHeadAnotherJobSaved(t *testing.T) {
	a, _ := dockerAgent(t, http.StatusOK)
	requestDocker(t, a, "/docker", "10.0.0.5")
	head := cachevolumes.Identity{BaseGeneration: 2, ImageDigest: strings.Repeat("b", 40), ContentDigest: strings.Repeat("c", 64)}
	var exposed []string
	a.dockerHeads = func(cachevolumes.Slot) (cachevolumes.Identity, error) { return head, nil }
	a.exposeDockerHead = func(_ context.Context, slot cachevolumes.Slot, path string, offered cachevolumes.Identity) error {
		if offered != head || slot.ID != dockerUse {
			t.Fatalf("offered %v for %v", offered, slot.ID)
		}
		exposed = append(exposed, path)
		return nil
	}
	code, response := requestDocker(t, a, "/docker-merge", "10.0.0.5")
	if code != http.StatusOK || response["merge"] != true || response["generation"] != float64(2) || response["source"] != strings.Repeat("e", 64)+"/"+cachevolumes.DockerMergeImageName {
		t.Fatalf("%d %v", code, response)
	}
	if len(exposed) != 1 || exposed[0] != filepath.Join(a.root, "pods", "uid", strings.Repeat("e", 64)) {
		t.Fatalf("exposed %v", exposed)
	}
}

func TestDockerMergeOffersNothingWhenNoOtherJobSaved(t *testing.T) {
	a, _ := dockerAgent(t, http.StatusOK)
	requestDocker(t, a, "/docker", "10.0.0.5")
	a.dockerHeads = func(slot cachevolumes.Slot) (cachevolumes.Identity, error) {
		return cachevolumes.Identity{BaseGeneration: slot.BaseGeneration}, nil
	}
	a.exposeDockerHead = func(context.Context, cachevolumes.Slot, string, cachevolumes.Identity) error {
		t.Fatal("offered the head the job started from")
		return nil
	}
	if code, response := requestDocker(t, a, "/docker-merge", "10.0.0.5"); code != http.StatusOK || response["merge"] != false {
		t.Fatalf("%d %v", code, response)
	}
	if code, _ := requestDocker(t, a, "/docker-merge", "10.0.0.9"); code != http.StatusForbidden {
		t.Fatalf("another pod's request answered %d", code)
	}
}

func TestDockerMergeOffersAssignedHeadForAnOlderMountedCopy(t *testing.T) {
	a, _ := dockerAgent(t, http.StatusOK)
	requestDocker(t, a, "/docker", "10.0.0.5")
	// Reproduce the durable journal from production: allocation pinned head 8,
	// while Attach cloned locally resident generation 7.
	slots, err := a.store.Snapshot()
	if err != nil || len(slots) != 1 {
		t.Fatalf("snapshot: %v %v", slots, err)
	}
	slot := slots[0]
	slot.BaseGeneration, slot.MountedGeneration, slot.Warm = 8, 7, true
	slot.ImageDigest, slot.ContentDigest = strings.Repeat("b", 40), strings.Repeat("c", 64)
	data, _ := json.Marshal(slot)
	files, _ := filepath.Glob(filepath.Join(a.root, "state", "*.json"))
	if len(files) != 1 {
		t.Fatalf("journal files: %v", files)
	}
	if err := os.WriteFile(files[0], data, 0600); err != nil {
		t.Fatal(err)
	}
	a.dockerHeads = func(cachevolumes.Slot) (cachevolumes.Identity, error) {
		return cachevolumes.Identity{BaseGeneration: 8}, nil
	}
	a.exposeDockerHead = func(context.Context, cachevolumes.Slot, string, cachevolumes.Identity) error { return nil }
	if code, response := requestDocker(t, a, "/docker-merge", "10.0.0.5"); code != http.StatusOK || response["merge"] != true || response["generation"] != float64(8) {
		t.Fatalf("stale mount did not receive its assigned head: %d %v", code, response)
	}
}

func TestDockerMergeWaitsForAnotherFinishedJobToPublish(t *testing.T) {
	a, _ := dockerAgent(t, http.StatusOK)
	requestDocker(t, a, "/docker", "10.0.0.5")
	slots, err := a.store.Snapshot()
	if err != nil || len(slots) != 1 {
		t.Fatalf("snapshot: %v %v", slots, err)
	}
	// Another job on this host mounted the same generation, finished with a
	// changed data root and is still uploading it: the head has not moved yet.
	sibling := slots[0]
	sibling.ID, sibling.PodName, sibling.PodUID = "44444444-4444-4444-8444-444444444444", "sibling", "sibling-uid"
	journal := filepath.Join(a.root, "state", sibling.ID+".json")
	writeSibling := func(state string) {
		sibling.State = state
		data, _ := json.Marshal(sibling)
		if err := os.WriteFile(journal, data, 0600); err != nil {
			t.Error(err)
		}
	}
	writeSibling("active")
	directory := filepath.Join(a.root, "pods", sibling.PodUID, sibling.Scope)
	if err := os.MkdirAll(directory, 0700); err != nil {
		t.Fatal(err)
	}
	report, _ := json.Marshal(cachevolumes.DockerReport{Clean: true, Changed: true})
	if err := os.WriteFile(filepath.Join(directory, cachevolumes.DockerReportName), report, 0600); err != nil {
		t.Fatal(err)
	}
	poll := dockerPublicationPoll
	dockerPublicationPoll = 10 * time.Millisecond
	t.Cleanup(func() { dockerPublicationPoll = poll })
	published := make(chan struct{})
	t.Cleanup(func() { <-published })
	go func() {
		time.Sleep(50 * time.Millisecond)
		writeSibling("sealed")
		close(published)
	}()
	a.dockerHeads = func(slot cachevolumes.Slot) (cachevolumes.Identity, error) {
		select {
		case <-published:
			return cachevolumes.Identity{BaseGeneration: slot.BaseGeneration + 1}, nil
		default:
			return cachevolumes.Identity{BaseGeneration: slot.BaseGeneration}, nil
		}
	}
	a.exposeDockerHead = func(context.Context, cachevolumes.Slot, string, cachevolumes.Identity) error { return nil }
	if code, response := requestDocker(t, a, "/docker-merge", "10.0.0.5"); code != http.StatusOK || response["merge"] != true || response["generation"] != float64(slots[0].BaseGeneration+1) {
		t.Fatalf("answered before the other job published: %d %v", code, response)
	}
}

func TestDockerMergeDoesNotWaitForAnUnchangedDataRoot(t *testing.T) {
	a, _ := dockerAgent(t, http.StatusOK)
	requestDocker(t, a, "/docker", "10.0.0.5")
	slots, _ := a.store.Snapshot()
	sibling := slots[0]
	sibling.ID, sibling.PodName, sibling.PodUID = "44444444-4444-4444-8444-444444444444", "sibling", "sibling-uid"
	data, _ := json.Marshal(sibling)
	if err := os.WriteFile(filepath.Join(a.root, "state", sibling.ID+".json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	directory := filepath.Join(a.root, "pods", sibling.PodUID, sibling.Scope)
	if err := os.MkdirAll(directory, 0700); err != nil {
		t.Fatal(err)
	}
	report, _ := json.Marshal(cachevolumes.DockerReport{Clean: true})
	if err := os.WriteFile(filepath.Join(directory, cachevolumes.DockerReportName), report, 0600); err != nil {
		t.Fatal(err)
	}
	if a.dockerPublicationPending(slots[0]) {
		t.Fatal("waited for a data root that will not publish")
	}
}
