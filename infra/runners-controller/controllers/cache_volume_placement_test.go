package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

func signalsClientServing(t *testing.T, signals scaling.Signals) *scaling.Client {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(signals)
	}))
	t.Cleanup(server.Close)
	tokenPath := filepath.Join(t.TempDir(), "token")
	_ = os.WriteFile(tokenPath, []byte("test-token"), 0o600)
	client := scaling.NewClient(server.URL)
	client.TokenPath = tokenPath
	return client
}

func createdPod(t *testing.T, r *RunnerPoolReconciler, name string) *corev1.Pod {
	t.Helper()
	pod := &corev1.Pod{}
	if err := r.Get(context.Background(), nn("tuist-runners", name), pod); err != nil {
		t.Fatalf("get created pod: %v", err)
	}
	return pod
}

func preferredKeys(pod *corev1.Pod) []string {
	if pod.Spec.Affinity == nil || pod.Spec.Affinity.NodeAffinity == nil {
		return nil
	}
	var keys []string
	for _, term := range pod.Spec.Affinity.NodeAffinity.PreferredDuringSchedulingIgnoredDuringExecution {
		for _, expr := range term.Preference.MatchExpressions {
			keys = append(keys, expr.Key)
		}
	}
	return keys
}

// preferredNodes are the Node names a Pod's placement preferences name.
func preferredNodes(pod *corev1.Pod) []string {
	if pod.Spec.Affinity == nil || pod.Spec.Affinity.NodeAffinity == nil {
		return nil
	}
	var nodes []string
	for _, term := range pod.Spec.Affinity.NodeAffinity.PreferredDuringSchedulingIgnoredDuringExecution {
		for _, field := range term.Preference.MatchFields {
			nodes = append(nodes, field.Values...)
		}
	}
	return nodes
}

func macOSReconciler(t *testing.T, pool *tuistv1.RunnerPool, signals scaling.Signals, objects ...*corev1.Pod) *RunnerPoolReconciler {
	t.Helper()
	scheme := mustScheme(t)
	builder := fake.NewClientBuilder().WithScheme(scheme).WithObjects(pool).WithStatusSubresource(&tuistv1.RunnerPool{})
	for _, pod := range objects {
		builder = builder.WithObjects(pod)
	}
	return &RunnerPoolReconciler{
		Client: builder.Build(), Scheme: scheme, DispatchURL: "http://dispatch",
		SignalsClient: signalsClientServing(t, signals),
	}
}

func TestCreateRunnerPrefersTheHostPickedForItsQueuedJob(t *testing.T) {
	pool := newPool("macos-ber1-26-1-1", "ghcr.io/tuist/macos:26.1.1", 1)
	r := macOSReconciler(t, pool, scaling.Signals{Fleet: pool.Name, Queued: 2, PreferredNodes: []string{"b03", "b09"}})

	name, err := r.createRunner(context.Background(), pool, 1)
	if err != nil {
		t.Fatalf("createRunner: %v", err)
	}

	pod := createdPod(t, r, name)
	if got := preferredNodes(pod); len(got) != 1 || got[0] != "b09" {
		t.Fatalf("preferred nodes = %v, want [b09]", got)
	}
	if got := preferredKeys(pod); len(got) != 1 || got[0] != podtemplate.GoldenNodeAffinityKey(pool.Spec.Image) {
		t.Fatalf("preferred node labels = %v, want only the golden one", got)
	}
}

func TestCreateRunnerAddsNoVolumePreferenceBeyondTheHostsWithRoom(t *testing.T) {
	pool := newPool("macos-ber1-26-1-1", "ghcr.io/tuist/macos:26.1.1", 1)
	r := macOSReconciler(t, pool, scaling.Signals{Fleet: pool.Name, Queued: 2, PreferredNodes: []string{"b03"}})

	name, err := r.createRunner(context.Background(), pool, 1)
	if err != nil {
		t.Fatalf("createRunner: %v", err)
	}

	if got := preferredNodes(createdPod(t, r, name)); len(got) != 0 {
		t.Fatalf("preferred nodes = %v, want none", got)
	}
}

func TestCreateRunnerKeepsTheGoldenPreferenceWithoutSignals(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("macos-ber1-26-1-1", "ghcr.io/tuist/macos:26.1.1", 1)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(pool).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch", SignalsClient: scaling.NewClient("http://127.0.0.1:0")}

	name, err := r.createRunner(context.Background(), pool, 0)
	if err != nil {
		t.Fatalf("createRunner: %v", err)
	}

	pod := createdPod(t, r, name)
	got := preferredKeys(pod)
	if len(got) != 1 || got[0] != podtemplate.GoldenNodeAffinityKey(pool.Spec.Image) {
		t.Fatalf("preferred node labels = %v, want only the golden one", got)
	}
	if nodes := preferredNodes(pod); len(nodes) != 0 {
		t.Fatalf("preferred nodes = %v, want none", nodes)
	}
}

func TestCreateRunnerAddsNoVolumePreferenceToLinuxPods(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-pool", 1, 1)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(pool).Build()
	r := &RunnerPoolReconciler{
		Client: c, Scheme: scheme, DispatchURL: "http://dispatch",
		SignalsClient: signalsClientServing(t, scaling.Signals{Fleet: pool.Name, Queued: 1, PreferredNodes: []string{"linux-01"}}),
	}

	name, err := r.createRunner(context.Background(), pool, 0)
	if err != nil {
		t.Fatalf("createRunner: %v", err)
	}

	if got := preferredNodes(createdPod(t, r, name)); len(got) != 0 {
		t.Fatalf("a Linux Pod got cache volume placement preferences %v", got)
	}
}

// An idle Pod takes the oldest queued job, so the Pods a reconcile creates
// take the preferences for the jobs after it. Starting from the first would
// send a second Pod to the host the idle Pod's job already fills.
func TestReconcileGivesNewPodsThePreferencesAfterTheIdlePods(t *testing.T) {
	pool := newPool("macos-ber1-26-1-1", "ghcr.io/tuist/macos:26.1.1", 3)
	idle := newRunnerPod("macos-ber1-26-1-1-runner-idle", pool.Spec.Image, corev1.PodPending, pool.Name)
	r := macOSReconciler(t, pool, scaling.Signals{Fleet: pool.Name, Queued: 3, PreferredNodes: []string{"b03", "b09", "b07"}}, idle)

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	pods := &corev1.PodList{}
	if err := r.List(context.Background(), pods); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	var got []string
	for i := range pods.Items {
		if pods.Items[i].Name == idle.Name {
			continue
		}
		got = append(got, strings.Join(preferredNodes(&pods.Items[i]), ","))
	}
	sort.Strings(got)
	if strings.Join(got, " ") != "b07 b09" {
		t.Fatalf("new Pods prefer %v, want b09 and b07", got)
	}
}
