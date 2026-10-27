package podagent

import (
	"context"
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

func TestCustomPublishesAFinishedPodWithoutWaitingForTheReportTick(t *testing.T) {
	m, _ := m2L(t)
	root := filepath.Join(m.Root, "custom")
	backend := &blockingCustomBackend{attachStarted: make(chan struct{}), sealStarted: make(chan struct{}), release: make(chan struct{})}
	store, err := cachevolumes.Open(root, backend)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	identity := cachevolumes.Identity{ID: "11111111-1111-4111-8111-111111111111", Scope: strings.Repeat("a", 64), Account: 1, CanPublish: true}
	if _, err := store.Acquire(context.Background(), identity, "job", "job"); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "pods", "job", identity.Scope, ".mounted"), []byte(identity.ID), 0600); err != nil {
		t.Fatal(err)
	}
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "job", Namespace: "runners", UID: types.UID("job"), Labels: map[string]string{"tuist.dev/runner": "true"}}, Spec: corev1.PodSpec{NodeName: "host"}, Status: corev1.PodStatus{Phase: corev1.PodRunning}}
	kube := fake.NewSimpleClientset(pod)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"action":"seal"}`))
	}))
	defer server.Close()
	c := &CustomVolumes{Root: root, Store: store, Kube: kube, Node: "host", Namespace: "runners", Space: m, URL: server.URL, HTTP: server.Client(), tokenValue: "token", tokenUntil: time.Now().Add(time.Hour), Running: func(context.Context, string) (bool, error) { return false, nil }}
	requests, reports := make(chan time.Time), make(chan time.Time)
	ctx, cancel := context.WithCancel(context.Background())
	stopped := make(chan struct{})
	go func() { defer close(stopped); _ = c.serve(ctx, requests, reports) }()
	defer func() {
		cancel()
		close(backend.release)
		<-stopped
	}()

	// The second tick is only received once the first one's listing, which saw the Pod running, is done.
	requests <- time.Now()
	requests <- time.Now()
	pod.Status.Phase = corev1.PodSucceeded
	if _, err := kube.CoreV1().Pods("runners").UpdateStatus(context.Background(), pod, metav1.UpdateOptions{}); err != nil {
		t.Fatal(err)
	}
	requests <- time.Now()
	// The branch can be sealed once the Pod is deleted; no report tick arrives meanwhile.
	if err := kube.CoreV1().Pods("runners").Delete(context.Background(), "job", metav1.DeleteOptions{}); err != nil {
		t.Fatal(err)
	}
	deadline := time.After(customSettleInterval + 3*time.Second)
	for {
		select {
		case <-backend.sealStarted:
			return
		case <-deadline:
			t.Fatal("the finished pod's branch waited for the report tick")
		case requests <- time.Now():
			time.Sleep(200 * time.Millisecond)
		}
	}
}
