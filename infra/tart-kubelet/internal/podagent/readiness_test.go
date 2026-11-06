package podagent

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

func TestPodStatusWithoutReadinessProbeIsReadyOnceVMHasIP(t *testing.T) {
	r, pod, entry := newRunningGuest(t, nil)

	status := mustPodStatus(t, r, pod)

	assertReady(t, status, true)
	if entry.Readiness != nil {
		t.Fatal("expected no prober for a Pod without a readinessProbe")
	}
}

func TestPodStatusWithPassingReadinessProbeBecomesReady(t *testing.T) {
	var hits atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		hits.Add(1)
		if req.URL.Path != "/ready" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	r, pod, entry := newRunningGuest(t, httpReadinessProbe(t, server.URL, "/ready"))

	// The first status is published before any probe has answered, so a
	// fresh Pod starts NotReady rather than Ready-by-default.
	assertReady(t, mustPodStatus(t, r, pod), false)

	waitUntil(t, func() bool { return entry.Readiness.Ready() })
	assertReady(t, mustPodStatus(t, r, pod), true)
	if hits.Load() == 0 {
		t.Fatal("expected the probe to reach the guest endpoint")
	}
}

func TestPodStatusWithFailingReadinessProbeStaysNotReady(t *testing.T) {
	var hits atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()
	r, pod, _ := newRunningGuest(t, httpReadinessProbe(t, server.URL, "/ready"))

	mustPodStatus(t, r, pod)
	waitUntil(t, func() bool { return hits.Load() >= 2 })
	status := mustPodStatus(t, r, pod)

	assertReady(t, status, false)
	if status.Phase != corev1.PodRunning {
		t.Fatalf("expected a failing probe to leave the Pod Running, got %q", status.Phase)
	}
	if status.ContainerStatuses[0].State.Running == nil {
		t.Fatalf("expected the container to stay Running, got %+v", status.ContainerStatuses[0].State)
	}
}

func TestPodStatusFollowsAFlappingReadinessProbe(t *testing.T) {
	var healthy atomic.Bool
	healthy.Store(true)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if healthy.Load() {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()
	probe := httpReadinessProbe(t, server.URL, "/ready")
	probe.FailureThreshold = 1
	r, pod, entry := newRunningGuest(t, probe)

	mustPodStatus(t, r, pod)
	waitUntil(t, func() bool { return entry.Readiness.Ready() })
	assertReady(t, mustPodStatus(t, r, pod), true)

	healthy.Store(false)
	waitUntil(t, func() bool { return !entry.Readiness.Ready() })
	assertReady(t, mustPodStatus(t, r, pod), false)

	healthy.Store(true)
	waitUntil(t, func() bool { return entry.Readiness.Ready() })
	assertReady(t, mustPodStatus(t, r, pod), true)
}

func TestReadinessProberAppliesThresholds(t *testing.T) {
	container := corev1.Container{ReadinessProbe: &corev1.Probe{
		ProbeHandler:     corev1.ProbeHandler{TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromInt32(1)}},
		SuccessThreshold: 2,
		FailureThreshold: 3,
	}}
	var transitions []bool
	p := newReadinessProber(container, time.Now(), false, func(ready, changed bool, _ error) {
		if changed {
			transitions = append(transitions, ready)
		}
	})
	failure := errors.New("refused")

	steps := []struct {
		err  error
		want bool
	}{
		{nil, false},     // one success is below successThreshold
		{failure, false}, // a failure resets the success streak
		{nil, false},
		{nil, true}, // two consecutive successes
		{failure, true},
		{failure, true},
		{nil, true}, // a success resets the failure streak
		{failure, true},
		{failure, true},
		{failure, false}, // three consecutive failures
		{nil, false},
		{nil, true},
	}
	for i, step := range steps {
		p.record(step.err)
		if got := p.Ready(); got != step.want {
			t.Fatalf("step %d: Ready() = %v, want %v", i, got, step.want)
		}
	}
	if want := []bool{true, false, true}; !slices.Equal(transitions, want) {
		t.Fatalf("transitions = %v, want %v", transitions, want)
	}
}

func TestReadinessProberSeedsFromThePublishedStatusOfTheSameVM(t *testing.T) {
	pod := &corev1.Pod{Status: corev1.PodStatus{ContainerStatuses: []corev1.ContainerStatus{
		{ContainerID: "tart://vm-a", Ready: true},
	}}}

	if !publishedReady(pod, "vm-a") {
		t.Fatal("expected a Ready status for the same VM to seed the prober Ready")
	}
	if publishedReady(pod, "vm-b") {
		t.Fatal("a Ready status for a different VM must not seed the prober")
	}
}

func TestReadinessProbeHonoursInitialDelay(t *testing.T) {
	var hits atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
	}))
	defer server.Close()
	container := corev1.Container{ReadinessProbe: httpReadinessProbe(t, server.URL, "/")}
	container.ReadinessProbe.InitialDelaySeconds = 60
	p := newReadinessProber(container, time.Now(), false, nil)

	p.Start("127.0.0.1")
	defer p.Stop()
	time.Sleep(1500 * time.Millisecond)

	if n := hits.Load(); n != 0 {
		t.Fatalf("expected no probe before initialDelaySeconds, got %d", n)
	}
	if p.Ready() {
		t.Fatal("expected NotReady before the first probe")
	}
}

func TestReadinessProbeTCPSocketResolvesNamedPort(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			_ = conn.Close()
		}
	}()
	port := listener.Addr().(*net.TCPAddr).Port
	container := corev1.Container{
		Ports: []corev1.ContainerPort{{Name: "health", ContainerPort: int32(port)}},
		ReadinessProbe: &corev1.Probe{
			ProbeHandler: corev1.ProbeHandler{TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromString("health")}},
		},
	}
	p := newReadinessProber(container, time.Now(), false, nil)

	if err := p.check(context.Background(), "127.0.0.1"); err != nil {
		t.Fatalf("expected the tcpSocket probe to pass, got %v", err)
	}
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}
	if err := p.check(context.Background(), "127.0.0.1"); err == nil {
		t.Fatal("expected the tcpSocket probe to fail once nothing listens")
	}
}

func TestReadinessProbeTimesOutAHangingGuest(t *testing.T) {
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		<-release
	}))
	defer server.Close()
	defer close(release)
	container := corev1.Container{ReadinessProbe: httpReadinessProbe(t, server.URL, "/")}
	container.ReadinessProbe.TimeoutSeconds = 1
	p := newReadinessProber(container, time.Now(), false, nil)

	started := time.Now()
	err := p.check(context.Background(), "127.0.0.1")

	if err == nil {
		t.Fatal("expected a hanging guest to fail the probe")
	}
	if elapsed := time.Since(started); elapsed > 3*time.Second {
		t.Fatalf("expected the probe to give up after its timeout, took %v", elapsed)
	}
}

func TestDeleteByKeyStopsAnInFlightReadinessProbe(t *testing.T) {
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		<-release
	}))
	defer server.Close()
	defer close(release)
	probe := httpReadinessProbe(t, server.URL, "/")
	probe.TimeoutSeconds = 30
	r, pod, entry := newRunningGuest(t, probe)
	mustPodStatus(t, r, pod)
	prober := entry.Readiness

	started := time.Now()
	if err := r.deleteByKey(context.Background(), pod.Namespace, pod.Name); err != nil {
		t.Fatalf("deleteByKey: %v", err)
	}

	if elapsed := time.Since(started); elapsed > 5*time.Second {
		t.Fatalf("expected deletion not to wait on the probe, took %v", elapsed)
	}
	select {
	case <-prober.done:
	case <-time.After(5 * time.Second):
		t.Fatal("expected the prober to exit once its VM was deleted")
	}
	if r.Store.Get(pod.Namespace, pod.Name) != nil {
		t.Fatal("expected the Store entry to be gone")
	}
}

func TestPodStatusWithUnsupportedReadinessProbeKeepsVMReadiness(t *testing.T) {
	r, pod, entry := newRunningGuest(t, &corev1.Probe{
		ProbeHandler: corev1.ProbeHandler{Exec: &corev1.ExecAction{Command: []string{"true"}}},
	})

	assertReady(t, mustPodStatus(t, r, pod), true)
	if entry.Readiness != nil {
		t.Fatal("expected no prober for a handler tart-kubelet cannot evaluate")
	}
}

// newRunningGuest sets up a Pod whose VM reads as running with the
// guest at 127.0.0.1: a fake `tart` that answers `ip`, and a decoy
// `tart run <vm>` process for IsRunning's pgrep.
func newRunningGuest(t *testing.T, probe *corev1.Probe) (*Reconciler, *corev1.Pod, *Entry) {
	t.Helper()
	if _, err := exec.LookPath("pgrep"); err != nil {
		t.Skip("pgrep not available on this host")
	}
	dir := t.TempDir()
	bin := filepath.Join(dir, "faketart")
	script := "#!/bin/sh\nif [ \"$1\" = ip ]; then echo 127.0.0.1; fi\nexit 0\n"
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}

	vmName := "vm-readiness-" + strconv.FormatInt(time.Now().UnixNano(), 36)
	ctx, cancel := context.WithCancel(context.Background())
	decoy := exec.CommandContext(ctx, "/bin/sh", "-c", "sleep 60; :", "tart", "run", vmName)
	if err := decoy.Start(); err != nil {
		cancel()
		t.Fatalf("start decoy: %v", err)
	}
	t.Cleanup(func() {
		cancel()
		_ = decoy.Wait()
	})
	tartClient := &tart.Client{Binary: bin, UserDataDir: filepath.Join(dir, "userdata")}
	waitUntil(t, func() bool {
		running, err := tartClient.IsRunning(context.Background(), vmName)
		return err == nil && running
	})

	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist", Name: "xcresult-processor-" + vmName},
		Spec: corev1.PodSpec{Containers: []corev1.Container{{
			Name:           "xcresult-processor",
			Image:          "ghcr.io/tuist/xcresult-processor:test",
			ReadinessProbe: probe,
		}}},
	}
	entry := &Entry{VMName: vmName, StartTS: metav1.Now(), BootObserved: true}
	store := NewStore()
	store.Put(pod.Namespace, pod.Name, entry)
	r := &Reconciler{Tart: tartClient, Store: store, NodeName: "mini-1"}
	t.Cleanup(func() {
		if entry.Readiness != nil {
			entry.Readiness.Stop()
		}
	})
	return r, pod, entry
}

func httpReadinessProbe(t *testing.T, serverURL, path string) *corev1.Probe {
	t.Helper()
	_, portString, err := net.SplitHostPort(serverURL[len("http://"):])
	if err != nil {
		t.Fatal(err)
	}
	port, err := strconv.Atoi(portString)
	if err != nil {
		t.Fatal(err)
	}
	return &corev1.Probe{
		ProbeHandler:  corev1.ProbeHandler{HTTPGet: &corev1.HTTPGetAction{Path: path, Port: intstr.FromInt32(int32(port))}},
		PeriodSeconds: 1,
	}
}

func mustPodStatus(t *testing.T, r *Reconciler, pod *corev1.Pod) *corev1.PodStatus {
	t.Helper()
	status, err := r.podStatus(context.Background(), pod)
	if err != nil {
		t.Fatalf("podStatus: %v", err)
	}
	if status == nil || status.Phase != corev1.PodRunning {
		t.Fatalf("expected a Running status, got %+v", status)
	}
	return status
}

func assertReady(t *testing.T, status *corev1.PodStatus, want bool) {
	t.Helper()
	wantCondition := corev1.ConditionFalse
	if want {
		wantCondition = corev1.ConditionTrue
	}
	if len(status.Conditions) != 1 || status.Conditions[0].Type != corev1.PodReady || status.Conditions[0].Status != wantCondition {
		t.Fatalf("expected PodReady=%s, got %+v", wantCondition, status.Conditions)
	}
	if len(status.ContainerStatuses) != 1 || status.ContainerStatuses[0].Ready != want {
		t.Fatalf("expected the container status to mirror Ready=%v, got %+v", want, status.ContainerStatuses)
	}
}

func waitUntil(t *testing.T, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for !condition() {
		if time.Now().After(deadline) {
			t.Fatal("condition not met within 10s")
		}
		time.Sleep(20 * time.Millisecond)
	}
}
