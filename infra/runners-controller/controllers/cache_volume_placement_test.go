package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
	"github.com/tuist/tuist/infra/runners-controller/internal/scaling"
)

var lfsVolumeLabel = "tuist.dev/cache-volume-" + strings.Repeat("a", 48)

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

func TestCreateRunnerPrefersHostsHoldingTheQueuedJobsVolumes(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("macos-ber1-26-1-1", "ghcr.io/tuist/macos:26.1.1", 1)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(pool).Build()
	r := &RunnerPoolReconciler{
		Client: c, Scheme: scheme, DispatchURL: "http://dispatch",
		SignalsClient: signalsClientServing(t, scaling.Signals{Fleet: pool.Name, Queued: 1, PreferredNodeLabels: []string{lfsVolumeLabel}}),
	}

	name, err := r.createRunner(context.Background(), pool)
	if err != nil {
		t.Fatalf("createRunner: %v", err)
	}

	got := preferredKeys(createdPod(t, r, name))
	want := []string{podtemplate.GoldenNodeAffinityKey(pool.Spec.Image), lfsVolumeLabel}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("preferred node labels = %v, want %v", got, want)
	}
}

func TestCreateRunnerKeepsTheGoldenPreferenceWithoutSignals(t *testing.T) {
	scheme := mustScheme(t)
	pool := newPool("macos-ber1-26-1-1", "ghcr.io/tuist/macos:26.1.1", 1)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(pool).Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch", SignalsClient: scaling.NewClient("http://127.0.0.1:0")}

	name, err := r.createRunner(context.Background(), pool)
	if err != nil {
		t.Fatalf("createRunner: %v", err)
	}

	got := preferredKeys(createdPod(t, r, name))
	if len(got) != 1 || got[0] != podtemplate.GoldenNodeAffinityKey(pool.Spec.Image) {
		t.Fatalf("preferred node labels = %v, want only the golden one", got)
	}
}

func TestCreateRunnerAddsNoVolumePreferenceToLinuxPods(t *testing.T) {
	scheme := mustScheme(t)
	pool := newLinuxKataPool("linux-pool", 1, 1)
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(pool).Build()
	r := &RunnerPoolReconciler{
		Client: c, Scheme: scheme, DispatchURL: "http://dispatch",
		SignalsClient: signalsClientServing(t, scaling.Signals{Fleet: pool.Name, Queued: 1, PreferredNodeLabels: []string{lfsVolumeLabel}}),
	}

	name, err := r.createRunner(context.Background(), pool)
	if err != nil {
		t.Fatalf("createRunner: %v", err)
	}

	for _, key := range preferredKeys(createdPod(t, r, name)) {
		if key == lfsVolumeLabel {
			t.Fatal("a Linux Pod got a cache volume placement preference")
		}
	}
}
