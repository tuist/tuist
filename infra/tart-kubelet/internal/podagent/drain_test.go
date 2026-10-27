package podagent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

const drainTestUID = "b1abef64-43be-40c8-b78d-49d18c261fed"

func TestDrainSurvivesReconcileRestartAndRequiresMatchingAcknowledgement(t *testing.T) {
	dir := t.TempDir()
	for i := 0; i < 2; i++ {
		waiting, err := requestGuestDrain(dir, drainTestUID)
		if err != nil || !waiting {
			t.Fatalf("pending drain: %v %v", waiting, err)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "drain-complete"), []byte("another-pod\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if waiting, err := requestGuestDrain(dir, drainTestUID); err != nil || !waiting {
		t.Fatalf("stale acknowledgement: %v %v", waiting, err)
	}
	if err := os.WriteFile(filepath.Join(dir, "drain-complete"), []byte(drainTestUID+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if waiting, err := requestGuestDrain(dir, drainTestUID); err != nil || waiting {
		t.Fatalf("completed drain: %v %v", waiting, err)
	}
}

func TestDrainRejectsSymlinksAndFIFOs(t *testing.T) {
	for _, name := range []string{"drain-request", "drain-complete"} {
		for _, kind := range []string{"symlink", "fifo"} {
			t.Run(name+"/"+kind, func(t *testing.T) {
				dir := t.TempDir()
				outside := filepath.Join(t.TempDir(), "outside")
				want := drainTestUID + "\n"
				if err := os.WriteFile(outside, []byte(want), 0600); err != nil {
					t.Fatal(err)
				}
				path := filepath.Join(dir, name)
				var err error
				if kind == "symlink" {
					err = os.Symlink(outside, path)
				} else {
					err = syscall.Mkfifo(path, 0600)
				}
				if err != nil {
					t.Fatal(err)
				}
				waiting, _ := requestGuestDrain(dir, drainTestUID)
				if !waiting {
					t.Fatal("unsafe guest file accepted as acknowledgement")
				}
				data, err := os.ReadFile(outside)
				if err != nil || string(data) != want {
					t.Fatal("modified a path outside the VM share")
				}
			})
		}
	}
}

func TestDrainSkipsABootedProcessorThatNeverPassedReadiness(t *testing.T) {
	r, pod, entry := newBootedProcessor(t)
	entry.Readiness.record(errors.New("connection refused"))

	assertDrain(t, r, pod, entry, false)
}

func TestDrainSkipsABootedProcessorWhoseGuestNeverHadAnIP(t *testing.T) {
	r, pod, entry := newBootedProcessor(t)
	entry.Readiness = nil

	assertDrain(t, r, pod, entry, false)
}

func TestDrainWaitsForABootedProcessorBeforeItsFirstProbe(t *testing.T) {
	r, pod, entry := newBootedProcessor(t)

	assertDrain(t, r, pod, entry, true)
}

func TestDrainWaitsForABootedProcessorThatWasReady(t *testing.T) {
	r, pod, entry := newBootedProcessor(t)
	entry.Readiness.record(nil)
	entry.Readiness.record(errors.New("connection refused"))
	if entry.Readiness.Ready() {
		t.Fatal("expected the failed probe to make the Pod NotReady")
	}

	assertDrain(t, r, pod, entry, true)
}

func TestDrainWaitsForARecoveredProcessorThatIsNotReady(t *testing.T) {
	r, pod, entry := newRunningGuest(t, tcpProbe())
	pod.UID = types.UID(drainTestUID)
	pod.Annotations = map[string]string{gracefulDrainAnnotation: "xcresult-v1"}
	entry.StatusDir = t.TempDir()
	entry.Readiness = newReadinessProber(pod.Spec.Containers[0], time.Now(), false, nil)
	entry.Readiness.record(errors.New("connection refused"))

	assertDrain(t, r, pod, entry, true)
}

func newBootedProcessor(t *testing.T) (*Reconciler, *corev1.Pod, *Entry) {
	t.Helper()
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:   "tuist",
			Name:        "xcresult-processor",
			UID:         types.UID(drainTestUID),
			Annotations: map[string]string{gracefulDrainAnnotation: "xcresult-v1"},
		},
		Spec: corev1.PodSpec{Containers: []corev1.Container{{Name: "xcresult-processor", ReadinessProbe: tcpProbe()}}},
	}
	entry := &Entry{
		VMName:    "vm-processor",
		Run:       &tart.RunHandle{},
		StatusDir: t.TempDir(),
		Readiness: newReadinessProber(pod.Spec.Containers[0], time.Now(), false, nil),
	}
	store := NewStore()
	store.Put(pod.Namespace, pod.Name, entry)
	return &Reconciler{Store: store}, pod, entry
}

func tcpProbe() *corev1.Probe {
	return &corev1.Probe{
		ProbeHandler:     corev1.ProbeHandler{TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromInt32(9092)}},
		FailureThreshold: 1,
	}
}

func assertDrain(t *testing.T, r *Reconciler, pod *corev1.Pod, entry *Entry, wantWaiting bool) {
	t.Helper()
	waiting, err := r.drainPod(context.Background(), pod)
	if err != nil || waiting != wantWaiting {
		t.Fatalf("drainPod = %v, %v; want waiting=%v", waiting, err, wantWaiting)
	}
	_, statErr := os.Stat(filepath.Join(entry.StatusDir, "drain-request"))
	if requested := statErr == nil; requested != wantWaiting {
		t.Fatalf("drain request written = %v, want %v", requested, wantWaiting)
	}
}
