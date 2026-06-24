package controllers

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	k8sfake "k8s.io/client-go/kubernetes/fake"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/runners-controller/internal/sessions"
)

type recorder struct {
	mu       sync.Mutex
	requests []sessions.StoppedRequest
}

func (r *recorder) handler(w http.ResponseWriter, req *http.Request) {
	body, _ := io.ReadAll(req.Body)
	var s sessions.StoppedRequest
	_ = json.Unmarshal(body, &s)
	r.mu.Lock()
	r.requests = append(r.requests, s)
	r.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

func (r *recorder) all() []sessions.StoppedRequest {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]sessions.StoppedRequest, len(r.requests))
	copy(out, r.requests)
	return out
}

func newReconciler(t *testing.T, pods []*corev1.Pod) (*PodLifecycleReconciler, *recorder, func()) {
	t.Helper()

	rec := &recorder{}
	server := httptest.NewServer(http.HandlerFunc(rec.handler))

	tokenPath := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenPath, []byte("tok"), 0o600); err != nil {
		t.Fatalf("write token: %v", err)
	}

	scheme := mustScheme(t)
	builder := fake.NewClientBuilder().WithScheme(scheme)
	for _, p := range pods {
		builder = builder.WithObjects(p)
	}
	c := builder.Build()

	sc := sessions.NewClient(server.URL + "/api/internal/runners")
	sc.TokenPath = tokenPath

	r := &PodLifecycleReconciler{
		Client:         c,
		Scheme:         scheme,
		SessionsClient: sc,
	}
	return r, rec, server.Close
}

func runnerPodWithTerminated(name string, finishedAt time.Time, phase corev1.PodPhase) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "tuist-runners",
			Labels:    map[string]string{"tuist.dev/runner": "true"},
		},
		Spec: corev1.PodSpec{Containers: []corev1.Container{{Name: "runner"}}},
		Status: corev1.PodStatus{
			Phase: phase,
			ContainerStatuses: []corev1.ContainerStatus{
				{
					Name: "runner",
					State: corev1.ContainerState{
						Terminated: &corev1.ContainerStateTerminated{
							FinishedAt: metav1.NewTime(finishedAt),
						},
					},
				},
			},
		},
	}
}

func TestPodLifecycle_ReportsStoppedOnSucceededPod(t *testing.T) {
	finished := time.Date(2026, 5, 26, 14, 23, 11, 0, time.UTC)
	pod := runnerPodWithTerminated("tuist-pod-1", finished, corev1.PodSucceeded)

	r, rec, stop := newReconciler(t, []*corev1.Pod{pod})
	defer stop()

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn("tuist-runners", "tuist-pod-1")}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}

	reqs := rec.all()
	if len(reqs) != 1 {
		t.Fatalf("got %d requests, want 1", len(reqs))
	}
	if reqs[0].PodName != "tuist-pod-1" {
		t.Errorf("pod_name = %q, want tuist-pod-1", reqs[0].PodName)
	}
	if !reqs[0].EndedAt.Equal(finished) {
		t.Errorf("ended_at = %v, want %v", reqs[0].EndedAt, finished)
	}
}

func TestPodLifecycle_ReportsStoppedOnFailedPod(t *testing.T) {
	finished := time.Date(2026, 5, 26, 14, 30, 0, 0, time.UTC)
	pod := runnerPodWithTerminated("tuist-pod-2", finished, corev1.PodFailed)

	r, rec, stop := newReconciler(t, []*corev1.Pod{pod})
	defer stop()

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn("tuist-runners", "tuist-pod-2")}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if got := len(rec.all()); got != 1 {
		t.Fatalf("got %d requests, want 1", got)
	}
}

func TestPodLifecycle_NoEmitOnRunningPod(t *testing.T) {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "tuist-pod-running",
			Namespace: "tuist-runners",
			Labels:    map[string]string{"tuist.dev/runner": "true"},
		},
		Spec:   corev1.PodSpec{Containers: []corev1.Container{{Name: "runner"}}},
		Status: corev1.PodStatus{Phase: corev1.PodRunning},
	}

	r, rec, stop := newReconciler(t, []*corev1.Pod{pod})
	defer stop()

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn("tuist-runners", "tuist-pod-running")}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if got := len(rec.all()); got != 0 {
		t.Fatalf("got %d requests, want 0 (Pod is alive)", got)
	}
}

func TestPodLifecycle_DeduplicatesAcrossReconciles(t *testing.T) {
	finished := time.Date(2026, 5, 26, 14, 23, 11, 0, time.UTC)
	pod := runnerPodWithTerminated("tuist-pod-3", finished, corev1.PodSucceeded)

	r, rec, stop := newReconciler(t, []*corev1.Pod{pod})
	defer stop()

	req := ctrl.Request{NamespacedName: nn("tuist-runners", "tuist-pod-3")}
	if _, err := r.Reconcile(context.Background(), req); err != nil {
		t.Fatalf("Reconcile 1: %v", err)
	}
	if _, err := r.Reconcile(context.Background(), req); err != nil {
		t.Fatalf("Reconcile 2: %v", err)
	}

	if got := len(rec.all()); got != 1 {
		t.Errorf("got %d requests, want 1 (second reconcile should dedupe)", got)
	}
}

func TestPodLifecycle_FallsBackToDeletionTimestamp(t *testing.T) {
	deletion := time.Date(2026, 5, 26, 15, 0, 0, 0, time.UTC)

	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:              "tuist-pod-deleting",
			Namespace:         "tuist-runners",
			Labels:            map[string]string{"tuist.dev/runner": "true"},
			DeletionTimestamp: &metav1.Time{Time: deletion},
			Finalizers:        []string{"tuist.dev/keep-for-test"},
		},
		Spec:   corev1.PodSpec{Containers: []corev1.Container{{Name: "runner"}}},
		Status: corev1.PodStatus{Phase: corev1.PodRunning},
	}

	r, rec, stop := newReconciler(t, []*corev1.Pod{pod})
	defer stop()

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn("tuist-runners", "tuist-pod-deleting")}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}

	reqs := rec.all()
	if len(reqs) != 1 {
		t.Fatalf("got %d requests, want 1", len(reqs))
	}
	if !reqs[0].EndedAt.Equal(deletion) {
		t.Errorf("ended_at = %v, want deletionTimestamp %v", reqs[0].EndedAt, deletion)
	}
}

func runnerPodExit(name string, exitCode int32, phase corev1.PodPhase) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: "tuist-runners",
			Labels:    map[string]string{"tuist.dev/runner": "true"},
		},
		Spec: corev1.PodSpec{Containers: []corev1.Container{{Name: "runner"}}},
		Status: corev1.PodStatus{
			Phase: phase,
			ContainerStatuses: []corev1.ContainerStatus{{
				Name: "runner",
				State: corev1.ContainerState{
					Terminated: &corev1.ContainerStateTerminated{
						ExitCode:   exitCode,
						FinishedAt: metav1.NewTime(time.Date(2026, 6, 23, 9, 37, 0, 0, time.UTC)),
					},
				},
			}},
		},
	}
}

func podLogGets(cs *k8sfake.Clientset) int {
	n := 0
	for _, a := range cs.Actions() {
		if a.GetVerb() == "get" && a.GetResource().Resource == "pods" && a.GetSubresource() == "log" {
			n++
		}
	}
	return n
}

func TestAbnormalEnd(t *testing.T) {
	deleting := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{DeletionTimestamp: &metav1.Time{Time: time.Now()}},
		Status:     corev1.PodStatus{Phase: corev1.PodRunning},
	}
	tests := []struct {
		name string
		pod  *corev1.Pod
		want bool
	}{
		{"clean exit 0", runnerPodExit("p", 0, corev1.PodSucceeded), false},
		{"non-zero exit", runnerPodExit("p", 1, corev1.PodFailed), true},
		{"sigkilled microVM teardown", runnerPodExit("p", 137, corev1.PodFailed), true},
		{"reaped while running (lost comm)", deleting, true},
		{"alive, not ending", &corev1.Pod{Status: corev1.PodStatus{Phase: corev1.PodRunning}}, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := abnormalEnd(tc.pod); got != tc.want {
				t.Errorf("abnormalEnd = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestPodLifecycle_CapturesDeathLogOnAbnormalExit(t *testing.T) {
	pod := runnerPodExit("tuist-pod-dead", 137, corev1.PodFailed)

	r, _, stop := newReconciler(t, []*corev1.Pod{pod})
	defer stop()
	cs := k8sfake.NewSimpleClientset(pod)
	r.Logs = cs

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn("tuist-runners", "tuist-pod-dead")}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if got := podLogGets(cs); got != 1 {
		t.Fatalf("pods/log gets = %d, want 1", got)
	}
}

func TestPodLifecycle_NoCaptureOnCleanExit(t *testing.T) {
	pod := runnerPodExit("tuist-pod-clean", 0, corev1.PodSucceeded)

	r, _, stop := newReconciler(t, []*corev1.Pod{pod})
	defer stop()
	cs := k8sfake.NewSimpleClientset(pod)
	r.Logs = cs

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn("tuist-runners", "tuist-pod-clean")}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	if got := podLogGets(cs); got != 0 {
		t.Fatalf("pods/log gets = %d, want 0 (clean exit)", got)
	}
}

func TestPodLifecycle_DeduplicatesDeathLogCapture(t *testing.T) {
	pod := runnerPodExit("tuist-pod-dead-dup", 1, corev1.PodFailed)

	r, _, stop := newReconciler(t, []*corev1.Pod{pod})
	defer stop()
	cs := k8sfake.NewSimpleClientset(pod)
	r.Logs = cs

	req := ctrl.Request{NamespacedName: nn("tuist-runners", "tuist-pod-dead-dup")}
	for i := 0; i < 2; i++ {
		if _, err := r.Reconcile(context.Background(), req); err != nil {
			t.Fatalf("Reconcile %d: %v", i, err)
		}
	}
	if got := podLogGets(cs); got != 1 {
		t.Errorf("pods/log gets = %d, want 1 (second reconcile should dedupe)", got)
	}
}

func TestPodLifecycle_NotFoundClearsCache(t *testing.T) {
	r, rec, stop := newReconciler(t, nil)
	defer stop()

	// Pre-seed the reported cache as if we'd already POSTed.
	key := "tuist-runners/tuist-pod-gone"
	r.reported.Store(key, struct{}{})

	// Reconcile with no Pod in the cluster — should NotFound and
	// clear the cache so a future Pod with the same name (rare,
	// names carry a random suffix) gets a fresh emission.
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn("tuist-runners", "tuist-pod-gone")}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}

	if _, present := r.reported.Load(key); present {
		t.Error("reported entry should be cleared on NotFound")
	}
	if got := len(rec.all()); got != 0 {
		t.Errorf("got %d requests, want 0 (Pod gone, nothing to send)", got)
	}
}
