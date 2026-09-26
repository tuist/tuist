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

	"github.com/tuist/tuist/infra/runners-controller/internal/cachevolumes"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes/fake"
	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"
)

type testBackend struct{}

func (testBackend) Attach(cachevolumes.Slot, string) error                  { return nil }
func (testBackend) Seal(cachevolumes.Slot, string) error                    { return nil }
func (testBackend) Delete(cachevolumes.Slot, string) error                  { return nil }
func (testBackend) Measure(cachevolumes.Slot, string) (int64, int64, error) { return 0, 100, nil }
func TestAcquireBindsSourceIPNodeUIDAndAuthorization(t *testing.T) {
	root := t.TempDir()
	s, err := cachevolumes.Open(root, testBackend{})
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "runner", Namespace: "runners", UID: types.UID("uid"), Labels: map[string]string{"tuist.dev/runner": "true"}}, Spec: corev1.PodSpec{NodeName: "node"}, Status: corev1.PodStatus{PodIP: "10.0.0.5", Phase: corev1.PodRunning}}
	authorized := false
	allow := true
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authorized = true
		if r.Header.Get("Authorization") != "Bearer agent-token" {
			t.Error("lost authorization")
		}
		var body map[string]any
		json.NewDecoder(r.Body).Decode(&body)
		if body["pod_name"] != "runner" || body["key"] != "gradle" {
			t.Error("lost execution identity")
		}
		if !allow {
			http.Error(w, "denied", 403)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"id": "00000000-0000-0000-0000-000000000001", "account_id": 1, "scope": strings.Repeat("a", 64)})
	}))
	defer upstream.Close()
	tokenPath := filepath.Join(root, "token")
	os.WriteFile(tokenPath, []byte("agent-token"), 0600)
	a := &agent{tokenPath: tokenPath, store: s, kube: fake.NewSimpleClientset(pod), namespace: "runners", node: "node", authorizeURL: upstream.URL, http: upstream.Client()}
	call := func(uid, ip string) int {
		body, _ := json.Marshal(request{PodName: "runner", PodUID: uid, Key: "gradle"})
		req := httptest.NewRequest("POST", "/acquire", bytes.NewReader(body))
		req.RemoteAddr = ip + ":1234"
		req.Header.Set("Authorization", "Bearer attacker-input")
		w := httptest.NewRecorder()
		a.serve(w, req)
		return w.Code
	}
	if got := call("uid", "10.0.0.6"); got != 403 || authorized {
		t.Fatal("accepted foreign IP", got)
	}
	if got := call("other-uid", "10.0.0.5"); got != 403 || authorized {
		t.Fatal("accepted foreign UID", got)
	}
	a.node = "other-node"
	if got := call("uid", "10.0.0.5"); got != 403 || authorized {
		t.Fatal("accepted foreign node", got)
	}
	a.node = "node"
	allow = false
	if got := call("uid", "10.0.0.5"); got != 403 {
		t.Fatal("ignored denied JWT", got)
	}
	if _, err := os.Stat(filepath.Join(root, "pods/uid")); !os.IsNotExist(err) {
		t.Fatal("exposed data before authorization")
	}
	allow = true
	if got := call("uid", "10.0.0.5"); got != 200 {
		t.Fatal("valid request rejected", got)
	}
}
func TestGoneWaitsForAPIDeletionAndRuntimeTeardown(t *testing.T) {
	kubelet := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "p", Namespace: "runners", UID: types.UID("u")}, Status: corev1.PodStatus{Phase: corev1.PodSucceeded}}
	a := &agent{kube: fake.NewSimpleClientset(pod), namespace: "runners", kubelet: kubelet, runtime: testRuntime{
		sandboxes: []*runtimeapi.PodSandbox{{Metadata: &runtimeapi.PodSandboxMetadata{Uid: "u"}, State: runtimeapi.PodSandboxState_SANDBOX_READY}},
	}}
	if gone, err := a.gone("p", "u"); err != nil || gone {
		t.Fatal("terminal pod reused before deletion")
	}
	if err := os.Mkdir(filepath.Join(kubelet, "u"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := a.kube.CoreV1().Pods("runners").Delete(context.Background(), "p", metav1.DeleteOptions{}); err != nil {
		t.Fatal(err)
	}
	if gone, err := a.gone("p", "u"); err != nil || gone {
		t.Fatal("reused before runtime teardown")
	}
	a.runtime = testRuntime{}
	if gone, err := a.gone("p", "u"); err != nil || !gone {
		t.Fatal("finished teardown not reclaimed")
	}
}
func TestRefusesRootFilesystem(t *testing.T) {
	root := t.TempDir()
	if err := dedicatedFilesystem(root, root); err == nil {
		t.Fatal("accepted kubelet filesystem")
	}
}
